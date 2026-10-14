import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:crypto/crypto.dart';
import 'package:flutter/foundation.dart';
import 'package:dio/dio.dart';
import 'package:dio/io.dart';
import 'package:uuid/uuid.dart';
import '../utils/otp_helper.dart';

enum MetaVerifiedStatusType {
  pending, // Verification pending
  needed, // Verification needed
  active, // Active / Subscribed
  expired, // Cookie expired / Session invalid
  notFound, // No Meta Verified subscription found
  error, // Network / parsing error
}

class MetaVerifiedCheckResult {
  final MetaVerifiedStatusType type;
  final String statusText;
  final String message;
  final bool isSuccess;

  const MetaVerifiedCheckResult({
    required this.type,
    required this.statusText,
    required this.message,
    this.isSuccess = true,
  });

  bool get isPending => type == MetaVerifiedStatusType.pending;
  bool get isNeeded => type == MetaVerifiedStatusType.needed;
  bool get isActive => type == MetaVerifiedStatusType.active;
}

class MetaCheckerService {
  static const String _defaultUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/124.0.0.0 Safari/537.36';

  /// Applies proxy settings to a Dio client (supports IP:Port, IP:Port:User:Pass, or URL format)
  static void applyProxy(Dio dio, String? proxyStr) {
    if (kIsWeb || proxyStr == null || proxyStr.trim().isEmpty) return;

    final p = proxyStr.trim();
    String hostPort = p;
    String? username;
    String? password;

    if (p.startsWith('http://') || p.startsWith('https://')) {
      final uri = Uri.parse(p);
      hostPort = '${uri.host}:${uri.port}';
      if (uri.userInfo.isNotEmpty) {
        final userParts = uri.userInfo.split(':');
        username = userParts[0];
        if (userParts.length > 1) password = userParts[1];
      }
    } else {
      final parts = p.split(':');
      if (parts.length >= 4) {
        hostPort = '${parts[0]}:${parts[1]}';
        username = parts[2];
        password = parts[3];
      } else if (parts.length == 2) {
        hostPort = '${parts[0]}:${parts[1]}';
      }
    }

    dio.httpClientAdapter = IOHttpClientAdapter(
      createHttpClient: () {
        final client = HttpClient();
        client.findProxy = (uri) => 'PROXY $hostPort';
        if (username != null && password != null) {
          client.authenticate = (uri, scheme, realm) {
            client.addCredentials(uri, realm ?? '', HttpClientBasicCredentials(username!, password!));
            return Future.value(true);
          };
        }
        client.badCertificateCallback = (cert, host, port) => true;
        return client;
      },
    );
  }

  /// Checks the Meta Verified subscription status on https://accountscenter.facebook.com/subscriptions
  static Future<MetaVerifiedCheckResult> checkMetaVerifiedStatus({
    required String cookie,
    String? proxy,
  }) async {
    final cleanCookie = cookie.trim();
    if (cleanCookie.isEmpty) {
      return const MetaVerifiedCheckResult(
        type: MetaVerifiedStatusType.error,
        statusText: 'Thiếu Cookie',
        message: 'Tài khoản chưa có Cookie để kiểm tra.',
        isSuccess: false,
      );
    }

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 20),
        validateStatus: (status) => status != null && status < 500,
      ));

      if (proxy != null && proxy.trim().isNotEmpty) {
        applyProxy(dio, proxy);
      }

      final headers = {
        'cookie': cleanCookie,
        'user-agent': _defaultUserAgent,
        'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/avif,image/webp,image/apng,*/*;q=0.8,application/signed-exchange;v=b3;q=0.7',
        'accept-language': 'en-US,en;q=0.9,vi;q=0.8',
        'sec-ch-ua': '"Chromium";v="124", "Google Chrome";v="124", "Not-A.Brand";v="99"',
        'sec-ch-ua-mobile': '?0',
        'sec-ch-ua-platform': '"Windows"',
        'sec-fetch-dest': 'document',
        'sec-fetch-mode': 'navigate',
        'sec-fetch-site': 'none',
        'sec-fetch-user': '?1',
        'upgrade-insecure-requests': '1',
      };

      final response = await dio.get(
        'https://accountscenter.facebook.com/subscriptions',
        options: Options(
          headers: headers,
          followRedirects: true,
          maxRedirects: 5,
        ),
      );

      final finalUrl = response.realUri.toString();
      final body = response.data?.toString() ?? '';
      final lowerBody = body.toLowerCase();

      // Check if session is expired or redirected to login
      if (finalUrl.contains('/login') ||
          finalUrl.contains('login.php') ||
          body.contains('id="login_form"') ||
          body.contains('name="login"') ||
          body.contains('login_homepage')) {
        return const MetaVerifiedCheckResult(
          type: MetaVerifiedStatusType.expired,
          statusText: 'Cookie hết hạn',
          message: 'Cookie Facebook đã hết hạn hoặc phiên đăng nhập đã bị đăng xuất (Facebook chuyển hướng về trang Login).',
          isSuccess: false,
        );
      }

      // Check if Checkpoint
      if (finalUrl.contains('checkpoint') || body.contains('checkpoint') || body.contains('/checkpoint/')) {
        return const MetaVerifiedCheckResult(
          type: MetaVerifiedStatusType.error,
          statusText: 'Checkpoint',
          message: 'Tài khoản đang bị Facebook Checkpoint xác minh danh tính.',
          isSuccess: false,
        );
      }

      // Check for Facebook 400 or server error page
      if (response.statusCode == 400 || body.contains('Sorry, something went wrong')) {
        return const MetaVerifiedCheckResult(
          type: MetaVerifiedStatusType.error,
          statusText: 'Lỗi phản hồi (400)',
          message: 'Facebook từ chối kết nối (Sorry, something went wrong). Cookie có thể thiếu các trường (sb, fr) hoặc bị Facebook chặn IP.',
          isSuccess: false,
        );
      }

      // Check for Verification Pending
      if (body.contains('Verification pending') ||
          lowerBody.contains('verification pending') ||
          lowerBody.contains('verification_pending') ||
          body.contains('Đang chờ xác minh')) {
        return const MetaVerifiedCheckResult(
          type: MetaVerifiedStatusType.pending,
          statusText: 'Verification pending',
          message: 'Hồ sơ đang trong hàng chờ Meta xét duyệt (Verification pending).',
          isSuccess: true,
        );
      }

      // Check for Verification Needed
      if (body.contains('Verification needed') ||
          lowerBody.contains('verification needed') ||
          lowerBody.contains('verification_needed') ||
          body.contains('Cần xác minh')) {
        return const MetaVerifiedCheckResult(
          type: MetaVerifiedStatusType.needed,
          statusText: 'Verification needed',
          message: 'Hồ sơ cần xác minh danh tính lại (Verification needed) - Hãy tải lên lại CCCD.',
          isSuccess: true,
        );
      }

      // Check for Active Meta Verified
      if (lowerBody.contains('meta verified') && (lowerBody.contains('active') || lowerBody.contains('hoạt động') || lowerBody.contains('đã đăng ký'))) {
        return const MetaVerifiedCheckResult(
          type: MetaVerifiedStatusType.active,
          statusText: 'Đã lên tích xanh (Active)',
          message: 'Tài khoản Meta Verified đang hoạt động (Đã có tích xanh).',
          isSuccess: true,
        );
      }

      // If page loaded but no Meta Verified record
      return const MetaVerifiedCheckResult(
        type: MetaVerifiedStatusType.notFound,
        statusText: 'Chưa có gói',
        message: 'Không tìm thấy gói Meta Verified nào trong danh sách Subscriptions.',
        isSuccess: true,
      );
    } catch (e) {
      return MetaVerifiedCheckResult(
        type: MetaVerifiedStatusType.error,
        statusText: 'Lỗi kiểm tra',
        message: 'Lỗi kết nối khi kiểm tra Meta Verified: $e',
        isSuccess: false,
      );
    }
  }

  /// Automatically logs into Facebook using Username, Password, and 2FA Key to extract Cookies
  static Future<String> loginAndExtractCookie({
    required String username,
    required String password,
    required String twoFactorKey,
    String? proxy,
  }) async {
    var cleanUser = username.trim();
    if (cleanUser.startsWith('@')) {
      cleanUser = cleanUser.substring(1).trim();
    }
    final cleanPass = password.trim();
    final clean2fa = twoFactorKey.trim();

    if (cleanUser.isEmpty || cleanPass.isEmpty) {
      throw Exception('Vui lòng cung cấp đầy đủ Tài khoản và Mật khẩu.');
    }

    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 25),
      receiveTimeout: const Duration(seconds: 30),
      validateStatus: (status) => true,
    ));

    if (proxy != null && proxy.trim().isNotEmpty) {
      applyProxy(dio, proxy);
    }

    const apiKey = '256002347743983';
    const apiSecret = '374e60f8b9bb6b8cbb30f78030438895';
    final deviceId = const Uuid().v4();

    String generateSig(Map<String, String> data) {
      final sortedKeys = data.keys.toList()..sort();
      final buffer = StringBuffer();
      for (final k in sortedKeys) {
        buffer.write('$k=${data[k]}');
      }
      buffer.write(apiSecret);
      return md5.convert(utf8.encode(buffer.toString())).toString();
    }

    String extractCookieString(dynamic json) {
      if (json is Map && json['session_cookies'] is List) {
        final list = json['session_cookies'] as List;
        final parts = <String>[];
        for (final item in list) {
          if (item is Map && item['name'] != null && item['value'] != null) {
            parts.add('${item['name']}=${item['value']}');
          }
        }
        return parts.join('; ');
      }
      return '';
    }

    // 1. Initial Authentication Request via official Facebook auth API
    final authData = <String, String>{
      'fb_api_req_friendly_name': 'authenticate',
      'locale': 'en',
      'format': 'json',
      'api_key': apiKey,
      'method': 'auth.login',
      'generate_session_cookies': '1',
      'generate_machine_id': '1',
      'email': cleanUser,
      'password': cleanPass,
      'device_id': deviceId,
    };
    authData['sig'] = generateSig(authData);

    final res = await dio.post(
      'https://b-api.facebook.com/method/auth.login',
      data: authData,
      options: Options(
        contentType: Headers.formUrlEncodedContentType,
        validateStatus: (status) => true,
      ),
    );

    dynamic jsonResp = res.data;
    if (jsonResp is String) {
      try {
        jsonResp = jsonDecode(jsonResp);
      } catch (_) {}
    }

    var cookieResult = extractCookieString(jsonResp);

    // 2. Check if 2FA Challenge is required
    Map<String, dynamic> errorData = {};
    if (jsonResp is Map && jsonResp['error_data'] != null) {
      if (jsonResp['error_data'] is Map) {
        errorData = Map<String, dynamic>.from(jsonResp['error_data']);
      } else if (jsonResp['error_data'] is String) {
        try {
          errorData = Map<String, dynamic>.from(jsonDecode(jsonResp['error_data']));
        } catch (_) {}
      }
    }

    final loginFirstFactor = errorData['login_first_factor']?.toString();
    if (cookieResult.isEmpty && loginFirstFactor != null && loginFirstFactor.isNotEmpty) {
      if (clean2fa.isEmpty) {
        throw Exception('Tài khoản yêu cầu mã xác thực 2FA nhưng chưa nhập Khóa bảo mật 2FA.');
      }

      final otp = await OtpHelper.fetchOtp(clean2fa);

      final twoFaData = <String, String>{
        'fb_api_req_friendly_name': 'authenticate',
        'locale': 'en',
        'format': 'json',
        'api_key': apiKey,
        'method': 'auth.login',
        'generate_session_cookies': '1',
        'generate_machine_id': '1',
        'email': cleanUser,
        'credentials_type': 'two_factor',
        'error_detail_type': 'button_with_disabled',
        'first_factor': loginFirstFactor,
        'twofactor_code': otp,
        'password': otp,
        'device_id': deviceId,
      };
      if (errorData['uid'] != null) {
        twoFaData['userid'] = errorData['uid'].toString();
      }
      if (errorData['machine_id'] != null) {
        twoFaData['machine_id'] = errorData['machine_id'].toString();
      }
      twoFaData['sig'] = generateSig(twoFaData);

      final twoFaRes = await dio.post(
        'https://b-api.facebook.com/method/auth.login',
        data: twoFaData,
        options: Options(
          contentType: Headers.formUrlEncodedContentType,
          validateStatus: (status) => true,
        ),
      );

      dynamic twoFaJson = twoFaRes.data;
      if (twoFaJson is String) {
        try {
          twoFaJson = jsonDecode(twoFaJson);
        } catch (_) {}
      }

      cookieResult = extractCookieString(twoFaJson);
      if (cookieResult.isEmpty && twoFaJson is Map) {
        final errTitle = twoFaJson['error_title'] ?? twoFaJson['error_msg'] ?? '';
        throw Exception('Xác thực 2FA không thành công: $errTitle. Vui lòng kiểm tra lại khóa 2FA.');
      }
    }

    // 3. Handle errors if still no cookie
    if (cookieResult.isEmpty) {
      final errCode = jsonResp is Map ? jsonResp['error_code'] : null;
      final errMsg = jsonResp is Map ? (jsonResp['error_msg']?.toString() ?? '') : '';
      final errTitle = errorData['error_title']?.toString() ?? '';

      if (errCode == 405 || errMsg.contains('checkpoint') || errTitle.contains('checkpoint')) {
        throw Exception('Tài khoản bị Facebook Checkpoint xác minh danh tính (956/282).');
      }
      if (errCode == 401 || errTitle.contains('Wrong Credentials') || errMsg.contains('Invalid username')) {
        throw Exception('Tài khoản hoặc mật khẩu không chính xác.');
      }
      throw Exception('Không thể tự động lấy Cookie: ${errMsg.isNotEmpty ? errMsg : (errTitle.isNotEmpty ? errTitle : "Lỗi $errCode")}');
    }

    // 4. Enrich with additional browser cookies (sb, datr) if missing
    if (!cookieResult.contains('sb=')) {
      try {
        final enrichRes = await dio.get(
          'https://mbasic.facebook.com/',
          options: Options(
            headers: {
              'cookie': cookieResult,
              'user-agent': _defaultUserAgent,
            },
            followRedirects: false,
            validateStatus: (status) => true,
          ),
        );
        final setCookies = enrichRes.headers['set-cookie'];
        if (setCookies != null) {
          for (final item in setCookies) {
            final firstPart = item.split(';')[0];
            final eqIdx = firstPart.indexOf('=');
            if (eqIdx != -1) {
              final key = firstPart.substring(0, eqIdx).trim();
              if ((key == 'sb' || key == 'datr') && !cookieResult.contains('$key=')) {
                cookieResult = '$cookieResult; $firstPart';
              }
            }
          }
        }
      } catch (_) {}
    }

    return cookieResult;
  }
}
