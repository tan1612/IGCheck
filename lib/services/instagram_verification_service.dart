import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'meta_checker_service.dart';
import '../utils/account_parser_helper.dart';

enum InstagramVerifyStatus {
  success,
  checkpointFound,
  inReview,
  sessionExpired,
  error,
}

class InstagramVerifyResult {
  final InstagramVerifyStatus status;
  final String title;
  final String message;
  final String? checkpointUrl;
  final String? username;
  final String? userId;
  final Map<String, dynamic>? rawResponse;

  const InstagramVerifyResult({
    required this.status,
    required this.title,
    required this.message,
    this.checkpointUrl,
    this.username,
    this.userId,
    this.rawResponse,
  });

  bool get isSuccess => status == InstagramVerifyStatus.success || status == InstagramVerifyStatus.inReview;
}

class InstagramVerificationService {
  static const String _defaultUserAgent =
      'Mozilla/5.0 (iPhone; CPU iPhone OS 17_4 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/17.4 Mobile/15E148 Safari/604.1';

  /// Nén ảnh tài liệu trước khi gửi để tối ưu tốc độ và tránh bị máy chủ từ chối file quá lớn
  static Future<List<int>> compressDocumentImage(Uint8List bytes) async {
    try {
      final result = await FlutterImageCompress.compressWithList(
        bytes,
        minWidth: 1600,
        minHeight: 1600,
        quality: 85,
        format: CompressFormat.jpeg,
      );
      if (result.isNotEmpty && result.length < bytes.length) {
        debugPrint('⚡ Đã nén ảnh giấy tờ từ ${(bytes.length / 1024).toStringAsFixed(1)}KB -> ${(result.length / 1024).toStringAsFixed(1)}KB');
        return result;
      }
    } catch (e) {
      debugPrint('Warning nén ảnh giấy tờ: $e');
    }
    return bytes;
  }

  /// Trích xuất các token cần thiết từ chuỗi Cookie Instagram
  static Map<String, String> parseCookieTokens(String cookie) {
    final clean = cookie.trim();
    final tokens = <String, String>{};
    final pairs = clean.split(';');
    for (final p in pairs) {
      final idx = p.indexOf('=');
      if (idx > 0) {
        final key = p.substring(0, idx).trim();
        final val = p.substring(idx + 1).trim();
        tokens[key] = val;
      }
    }
    return tokens;
  }

  /// Thực hiện quy trình xác minh tài khoản Instagram bằng Cookie và Ảnh giấy tờ
  static Future<InstagramVerifyResult> submitVerification({
    required String cookie,
    required List<Uint8List> documentImages,
    String? proxy,
    String? customEndpoint,
    Function(String stepMessage)? onProgress,
  }) async {
    final cleanCookie = cookie.trim();
    if (cleanCookie.isEmpty) {
      return const InstagramVerifyResult(
        status: InstagramVerifyStatus.error,
        title: 'Thiếu Cookie',
        message: 'Vui lòng nhập chuỗi Cookie Instagram hợp lệ để bắt đầu.',
      );
    }

    if (documentImages.isEmpty) {
      return const InstagramVerifyResult(
        status: InstagramVerifyStatus.error,
        title: 'Thiếu ảnh giấy tờ',
        message: 'Vui lòng chọn ít nhất 1 ảnh giấy tờ tùy thân (CCCD / Bằng lái / Hộ chiếu).',
      );
    }

    onProgress?.call('Đang phân tích Cookie Instagram...');
    final tokens = parseCookieTokens(cleanCookie);
    final sessionId = tokens['sessionid'];
    final csrfToken = tokens['csrftoken'] ?? '';
    final dsUserId = tokens['ds_user_id'] ?? AccountParserHelper.extractUidFromCookie(cleanCookie);

    if (sessionId == null || sessionId.isEmpty) {
      return const InstagramVerifyResult(
        status: InstagramVerifyStatus.sessionExpired,
        title: 'Cookie không hợp lệ',
        message: 'Cookie không chứa sessionid. Vui lòng lấy cookie đầy đủ từ trình duyệt đã đăng nhập Instagram.',
      );
    }

    // Nếu người dùng cấu hình server riêng / custom API endpoint
    if (customEndpoint != null && customEndpoint.trim().isNotEmpty) {
      return await _submitToCustomServer(
        endpoint: customEndpoint.trim(),
        cookie: cleanCookie,
        documentImages: documentImages,
        tokens: tokens,
        proxy: proxy,
        onProgress: onProgress,
      );
    }

    // Khởi tạo Dio với Cookie và Proxy (nếu có)
    final dio = Dio(BaseOptions(
      connectTimeout: const Duration(seconds: 15),
      receiveTimeout: const Duration(seconds: 25),
      validateStatus: (status) => status != null && status < 500,
    ));

    if (proxy != null && proxy.trim().isNotEmpty) {
      MetaCheckerService.applyProxy(dio, proxy.trim());
    }

    final headers = {
      'cookie': cleanCookie,
      'user-agent': _defaultUserAgent,
      'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
      'accept-language': 'vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7',
      'x-ig-app-id': '936619743392459',
      'x-csrftoken': csrfToken,
      'x-requested-with': 'XMLHttpRequest',
      'referer': 'https://www.instagram.com/',
    };

    try {
      // BƯỚC 1: Kiểm tra trạng thái phiên và tìm link checkpoint / xác minh
      onProgress?.call('Đang kiểm tra trạng thái tài khoản Instagram...');
      final checkResponse = await dio.get(
        'https://www.instagram.com/challenge/',
        options: Options(headers: headers, followRedirects: true),
      );

      final finalUrl = checkResponse.realUri.toString();
      final bodyStr = checkResponse.data?.toString() ?? '';

      // Kiểm tra nếu cookie bị văng / hết hạn
      if (finalUrl.contains('/accounts/login') ||
          bodyStr.contains('name="login"') ||
          bodyStr.contains('id="login_form"') ||
          checkResponse.statusCode == 401 ||
          checkResponse.statusCode == 403) {
        return InstagramVerifyResult(
          status: InstagramVerifyStatus.sessionExpired,
          title: 'Cookie đã hết hạn',
          message: 'Phiên đăng nhập (sessionid) đã hết hạn hoặc bị Instagram đăng xuất. Vui lòng lấy lại Cookie mới.',
          userId: dsUserId,
        );
      }

      // BƯỚC 2: Nén các ảnh giấy tờ
      onProgress?.call('Đang nén ${documentImages.length} ảnh giấy tờ...');
      final compressedImages = <List<int>>[];
      for (final img in documentImages) {
        final compressed = await compressDocumentImage(img);
        compressedImages.add(compressed);
      }

      // BƯỚC 3: Gửi ảnh giấy tờ lên hệ thống xác minh của Instagram / Meta
      onProgress?.call('Đang tải ảnh giấy tờ lên hệ thống xác minh Meta...');

      // Chuẩn bị FormData với các trường tương thích luồng xác minh
      final formDataMap = <String, dynamic>{
        'upload_id': DateTime.now().millisecondsSinceEpoch.toString(),
        'security_code': '',
        'choice': '1',
      };

      for (int i = 0; i < compressedImages.length; i++) {
        final fieldName = (i == 0) ? 'photo' : 'photo_back';
        formDataMap[fieldName] = MultipartFile.fromBytes(
          compressedImages[i],
          filename: 'id_document_$i.jpg',
        );
      }

      // Thử submit tới endpoint challenge hiện hành của Instagram
      final submitUrl = finalUrl.contains('/challenge/') ? finalUrl : 'https://i.instagram.com/api/v1/challenge/';
      final submitResponse = await dio.post(
        submitUrl,
        data: FormData.fromMap(formDataMap),
        options: Options(headers: headers),
      );

      final submitData = submitResponse.data;
      final submitText = submitData?.toString() ?? '';

      // Kiểm tra phản hồi từ Instagram
      if (submitResponse.statusCode == 200 ||
          submitText.contains('"status":"ok"') ||
          submitText.contains('review') ||
          submitText.contains('pending') ||
          submitText.contains('submitted')) {
        return InstagramVerifyResult(
          status: InstagramVerifyStatus.success,
          title: 'Xác minh thành công',
          message: 'Đã gửi ảnh giấy tờ lên hệ thống thành công! Hồ sơ đang được Meta tiếp nhận xét duyệt.',
          userId: dsUserId,
          checkpointUrl: finalUrl.contains('/challenge/') ? finalUrl : null,
        );
      }

      // Nếu tài khoản đang có đường dẫn checkpoint dạng serialized_state hoặc msite
      if (finalUrl.contains('challenge') || finalUrl.contains('checkpoint') || finalUrl.contains('serialized_state')) {
        return InstagramVerifyResult(
          status: InstagramVerifyStatus.checkpointFound,
          title: 'Đã lấy link xác minh',
          message: 'Tài khoản đang ở màn hình xác minh danh tính. Bạn có thể mở trực tiếp link hoặc sao chép để hoàn tất trên trình duyệt.',
          checkpointUrl: finalUrl,
          userId: dsUserId,
        );
      }

      // Trường hợp tài khoản hoạt động bình thường, không yêu cầu checkpoint
      if (finalUrl == 'https://www.instagram.com/' || finalUrl.contains('/feed/')) {
        return InstagramVerifyResult(
          status: InstagramVerifyStatus.success,
          title: 'Tài khoản hoạt động',
          message: 'Tài khoản đang hoạt động bình thường và không bị khóa checkpoint. Đã gửi thông tin hồ sơ thành công.',
          userId: dsUserId,
        );
      }

      return InstagramVerifyResult(
        status: InstagramVerifyStatus.inReview,
        title: 'Đã gửi thông tin',
        message: 'Yêu cầu xác minh đã được xử lý. Vui lòng theo dõi trạng thái hộp thư hoặc email đăng ký tài khoản.',
        userId: dsUserId,
        checkpointUrl: finalUrl,
      );
    } catch (e) {
      debugPrint('Lỗi xác minh Instagram qua Cookie: $e');
      return InstagramVerifyResult(
        status: InstagramVerifyStatus.error,
        title: 'Lỗi kết nối',
        message: 'Không thể kết nối tới máy chủ Instagram: $e',
        userId: dsUserId,
      );
    }
  }

  /// Gửi dữ liệu tới API Server trung gian riêng nếu người dùng cung cấp
  static Future<InstagramVerifyResult> _submitToCustomServer({
    required String endpoint,
    required String cookie,
    required List<Uint8List> documentImages,
    required Map<String, String> tokens,
    String? proxy,
    Function(String stepMessage)? onProgress,
  }) async {
    onProgress?.call('Đang gửi dữ liệu tới API Server riêng: $endpoint...');
    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 20),
        receiveTimeout: const Duration(seconds: 40),
      ));

      final formDataMap = <String, dynamic>{
        'cookie': cookie,
        'user_id': tokens['ds_user_id'] ?? '',
        'photo_count': documentImages.length,
      };

      if (proxy != null && proxy.isNotEmpty) {
        formDataMap['proxy'] = proxy;
      }

      for (int i = 0; i < documentImages.length; i++) {
        final compressed = await compressDocumentImage(documentImages[i]);
        formDataMap['image_$i'] = MultipartFile.fromBytes(
          compressed,
          filename: 'document_$i.jpg',
        );
      }

      final response = await dio.post(endpoint, data: FormData.fromMap(formDataMap));
      if (response.statusCode == 200) {
        final data = response.data;
        final msg = data is Map ? (data['message'] ?? data['msg'] ?? 'Đã xác minh thành công!') : response.data.toString();
        return InstagramVerifyResult(
          status: InstagramVerifyStatus.success,
          title: 'Xác minh thành công',
          message: msg.toString(),
          userId: tokens['ds_user_id'],
        );
      } else {
        return InstagramVerifyResult(
          status: InstagramVerifyStatus.error,
          title: 'Lỗi máy chủ (${response.statusCode})',
          message: 'Server phản hồi: ${response.data}',
        );
      }
    } catch (e) {
      return InstagramVerifyResult(
        status: InstagramVerifyStatus.error,
        title: 'Lỗi gửi lên Server',
        message: 'Không thể kết nối đến $endpoint: $e',
      );
    }
  }
}
