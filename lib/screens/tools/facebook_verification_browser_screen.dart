import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';
import 'package:provider/provider.dart';

import '../../services/instagram_verification_service.dart';
import '../../services/facebook_web_session_service.dart';
import '../../services/notification_service.dart';
import '../../models/document_profile_name.dart';

/// Uses the real Facebook wizard rather than guessing its upload endpoint.
class FacebookVerificationBrowserScreen extends StatefulWidget {
  final String cookie;
  final List<Uint8List> documentImages;
  final String documentType;
  final DocumentProfileName? profileName;
  final Uint8List? avatarImage;

  const FacebookVerificationBrowserScreen({
    super.key,
    required this.cookie,
    required this.documentImages,
    required this.documentType,
    this.profileName,
    this.avatarImage,
  });

  @override
  State<FacebookVerificationBrowserScreen> createState() =>
      _FacebookVerificationBrowserScreenState();
}

class _FacebookVerificationBrowserScreenState
    extends State<FacebookVerificationBrowserScreen> {
  static Future<void> _pendingCleanup = Future<void>.value();
  late final Future<void> _preparation;
  InAppWebViewController? _controller;
  HeadlessInAppWebView? _statusProbe;
  Timer? _statusTimer;
  bool _statusBusy = false;
  bool _statusStarted = false;
  CookieManager? _cookies;
  Timer? _timer;
  String _script = '';
  String _profileScript = '';
  String _profileStage = 'done';
  String _currentProfileName = '';
  bool _profileSessionMatched = false;
  bool _avatarFilled = false;
  bool _avatarOpened = false;
  Map<String, String>? _avatar;
  String _message = 'Đang chuẩn bị phiên Facebook...';
  String? _uid;
  String? _verificationUrl;
  bool _busy = false;
  bool _loading = true;
  bool _paused = false;
  bool _triggered = false;
  bool _mobileMode = false;
  bool _submitted = false;
  bool _finished = false;
  bool _cleaning = false;
  bool _canPop = false;
  Future<bool>? _cleanupFuture;
  String? _lastNotifiedError;
  Set<int> _uploaded = {};
  late List<Map<String, String>> _images;
  DateTime _lastProgress = DateTime.now();

  static const _desktopUserAgent =
      'Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36';
  static const _mobileUserAgent =
      'Mozilla/5.0 (Linux; Android 13; Pixel 7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Mobile Safari/537.36';

  Future<void> _enableMobileVerification() async {
    final settings = await _controller!.getSettings() ?? InAppWebViewSettings();
    settings.userAgent = _mobileUserAgent;
    settings.preferredContentMode = UserPreferredContentMode.MOBILE;
    await _controller!.setSettings(settings: settings);
    if (defaultTargetPlatform == TargetPlatform.windows) {
      // Match Chrome's phone Device Mode, including viewport and touch support.
      await _controller!.callDevToolsProtocolMethod(
        methodName: 'Emulation.setDeviceMetricsOverride',
        parameters: {
          'width': 400,
          'height': 866,
          'deviceScaleFactor': 1,
          'mobile': true,
        },
      );
      await _controller!.callDevToolsProtocolMethod(
        methodName: 'Emulation.setTouchEmulationEnabled',
        parameters: {'enabled': true, 'maxTouchPoints': 5},
      );
    }
    if (mounted) setState(() => _mobileMode = true);
  }

  static bool _trusted(Uri? uri) =>
      uri?.scheme == 'https' &&
      const {
        'accountscenter.facebook.com',
        'm.facebook.com',
        'www.facebook.com',
      }.contains(uri?.host);

  @override
  void initState() {
    super.initState();
    _preparation = _prepare();
  }

  Future<void> _prepare() async {
    try {
      await _pendingCleanup;
      if (!mounted) return;
      if (kIsWeb ||
          !{
            TargetPlatform.windows,
            TargetPlatform.iOS,
          }.contains(defaultTargetPlatform)) {
        throw StateError('Luồng trình duyệt này hỗ trợ Windows và iOS.');
      }
      final tokens = InstagramVerificationService.parseCookieTokens(
        widget.cookie,
      );
      if ((tokens['c_user'] ?? '').isEmpty || (tokens['xs'] ?? '').isEmpty) {
        throw StateError('Cookie Facebook phải có đủ c_user và xs.');
      }
      _uid = tokens['c_user'];
      _script = await rootBundle.loadString('assets/facebook_verification.js');
      if (widget.profileName != null || widget.avatarImage != null) {
        _profileScript = await rootBundle.loadString(
          'assets/facebook_profile_update.js',
        );
        _profileStage = widget.profileName != null ? 'name' : 'avatar';
        if (widget.profileName != null && !widget.profileName!.isValid) {
          throw StateError('Họ tên đọc từ giấy tờ chưa hợp lệ.');
        }
        if (widget.avatarImage != null) {
          final bytes = widget.avatarImage!;
          final png = bytes.length > 3 && bytes[0] == 137 && bytes[1] == 80;
          final jpeg =
              bytes.length > 2 &&
              bytes[0] == 255 &&
              bytes[1] == 216 &&
              bytes[2] == 255;
          if (!png && !jpeg) {
            throw StateError('Avatar phải là ảnh JPEG hoặc PNG.');
          }
          _avatar = {
            'base64': base64Encode(bytes),
            'name': png ? 'avatar.png' : 'avatar.jpg',
            'mime': png ? 'image/png' : 'image/jpeg',
          };
        }
      }
      if (widget.documentImages.isEmpty || widget.documentImages.length > 2) {
        throw StateError('Vui lòng chọn một hoặc hai ảnh giấy tờ.');
      }
      _images = widget.documentImages.indexed.map((entry) {
        final (index, bytes) = entry;
        final png = bytes.length > 3 && bytes[0] == 137 && bytes[1] == 80;
        final jpeg =
            bytes.length > 2 &&
            bytes[0] == 255 &&
            bytes[1] == 216 &&
            bytes[2] == 255;
        if (!png && !jpeg) {
          throw StateError('Ảnh giấy tờ phải ở định dạng JPEG hoặc PNG.');
        }
        return {
          'name': 'document_$index.${png ? 'png' : 'jpg'}',
          'mime': png ? 'image/png' : 'image/jpeg',
          'base64': base64Encode(bytes),
        };
      }).toList();
      _cookies = CookieManager.instance();
      // Remove earlier account sessions before installing this account's cookie.
      final cleared = await FacebookWebSessionService.clear();
      if (!cleared) {
        throw StateError(
          'Chưa dọn sạch được phiên web cũ. Hãy đóng app và thử lại trước khi nhập cookie khác.',
        );
      }
      for (final entry in tokens.entries) {
        if (!mounted) {
          return;
        }
        if (entry.value.isEmpty) continue;
        final ok = await _cookies!.setCookie(
          url: WebUri('https://www.facebook.com/'),
          name: entry.key,
          value: entry.value,
          domain: '.facebook.com',
          path: '/',
          isSecure: true,
          isHttpOnly: entry.key == 'xs',
        );
        if (!ok) {
          throw StateError('Không thể khởi tạo cookie trong trình duyệt.');
        }
      }
      if (!mounted) {
        return;
      }
      setState(() => _message = 'Đang mở m.facebook.com bằng cookie...');
      _lastProgress = DateTime.now();
      _timer = Timer.periodic(const Duration(seconds: 2), (_) => _tick());
      setState(() => _loading = false);
    } catch (e) {
      if (mounted) {
        _pause('Không thể mở phiên xác minh: $e');
      }
    }
  }

  void _pause(String message) {
    if (!mounted || _finished) return;
    setState(() {
      _paused = true;
      _message = message;
    });
    unawaited(
      _controller
              ?.evaluateJavascript(
                source: 'window.__igcheckSuppressAvatarPicker = false;',
              )
              .catchError((_) => null) ??
          Future.value(),
    );
    if (_lastNotifiedError != message) {
      _lastNotifiedError = message;
      unawaited(
        context.read<NotificationService>().showLocalNotification(
          'Facebook: cần kiểm tra',
          message,
          'facebook_verification',
        ),
      );
    }
  }

  Future<void> _updateProfileStep() async {
    if (!_profileSessionMatched) {
      final response = await _controller!
          .callAsyncJavaScript(
            functionBody:
                '''
        if(document.querySelector('input[type="password"]'))return {error:'Facebook chưa đăng nhập được bằng cookie.'};
        try {
          const user=require('CurrentUserInitialData');
          if(String(user.ACCOUNT_ID || '')!==${jsonEncode(_uid)})return {error:'Phiên Facebook không khớp tài khoản cần cập nhật.'};
          return {matched:true,name:user.NAME || ''};
        }catch(_){return {matched:false};}
      ''',
          )
          .timeout(const Duration(seconds: 10));
      final value = response?.value;
      if (value is! Map) return;
      if (value['error'] != null) {
        _pause(value['error'].toString());
        return;
      }
      if (value['matched'] != true) return;
      _currentProfileName = value['name']?.toString() ?? '';
      _profileSessionMatched = true;
      String normalizeName(String name) => name.trim().replaceAll(RegExp(r'\s+'), ' ').toLowerCase();
      if (_profileStage == 'name' &&
          normalizeName(_currentProfileName) == normalizeName(widget.profileName!.fullName)) {
        _profileStage = _avatar != null ? 'avatar' : 'done';
        if (_profileStage == 'done') {
          setState(() => _message = 'Tên Facebook đã khớp giấy tờ; tiếp tục xác minh.');
          return;
        }
      }
    }
    if (_profileStage == 'avatar' && !_avatarOpened) {
      _avatarOpened = true;
      await _controller!.loadUrl(
        urlRequest: URLRequest(
          url: WebUri(
            'https://www.facebook.com/profile.php?id=${Uri.encodeComponent(_uid!)}',
          ),
        ),
      );
      _lastProgress = DateTime.now();
      return;
    }
    final args = jsonEncode({
      'stage': _profileStage,
      'uid': _uid,
      'currentName': _currentProfileName,
      'name': widget.profileName?.toJson(),
      'avatar': _avatar,
      'avatarFilled': _avatarFilled,
    });
    final value = await _controller!
        .evaluateJavascript(
          source: '$_profileScript\nwindow.IGCheckProfile.step($args);',
        )
        .timeout(const Duration(seconds: 15));
    if (!mounted || value is! Map) return;
    final state = value['state'];
    final message = value['message']?.toString() ?? 'Đang cập nhật hồ sơ...';
    if (state == 'error') {
      _pause(message);
      return;
    }
    if (state == 'navigate') {
      final url = Uri.tryParse(value['url']?.toString() ?? '');
      if (!_trusted(url)) throw StateError('Invalid profile navigation');
      await _controller!.loadUrl(
        urlRequest: URLRequest(url: WebUri(url.toString())),
      );
    } else if (state == 'name_submitted') {
      _profileStage = 'name_saving';
    } else if (state == 'name_saved') {
      _profileStage = 'name_check';
    } else if (state == 'name_confirmed') {
      _profileStage = _avatar != null ? 'avatar' : 'done';
    } else if (state == 'avatar_filled') {
      _avatarFilled = true;
    } else if (state == 'avatar_submitted') {
      _profileStage = 'avatar_saving';
    } else if (state == 'avatar_confirmed') {
      _profileStage = 'done';
      await _controller!.loadUrl(
        urlRequest: URLRequest(url: WebUri('https://m.facebook.com/')),
      );
    }
    if (state != 'waiting') _lastProgress = DateTime.now();
    setState(() => _message = message);
  }

  Future<bool> _cleanSession() => _cleanupFuture ??= (() async {
    _cleaning = true;
    _statusTimer?.cancel();
    try {
      await _statusProbe?.dispose();
    } catch (_) {
      /* Continue cleanup. */
    }
    _statusProbe = null;
    final controller = _controller;
    if (controller != null) {
      try {
        await controller.stopLoading().timeout(const Duration(seconds: 5));
        await controller
            .loadUrl(urlRequest: URLRequest(url: WebUri('about:blank')))
            .timeout(const Duration(seconds: 5));
      } catch (_) {
        /* Store cleanup below also works without the page. */
      }
    }
    return FacebookWebSessionService.clear(controller: controller);
  })();

  Future<void> _startStatusProbe() async {
    if (_statusStarted || _finished) return;
    _statusStarted = true;
    // A second read-only page avoids interrupting the document POST or
    // navigating away from an upload that may still be in progress.
    _statusProbe = HeadlessInAppWebView(
      initialSize: const Size(1000, 800),
      initialUrlRequest: URLRequest(
        url: WebUri(
          'https://accountscenter.facebook.com/meta_verified/?entrypoint=accounts_center_more_from_meta',
        ),
      ),
      initialSettings: InAppWebViewSettings(
        userAgent: _desktopUserAgent,
        useShouldOverrideUrlLoading: true,
      ),
      shouldOverrideUrlLoading: (_, action) async =>
          _trusted(action.request.url)
          ? NavigationActionPolicy.ALLOW
          : NavigationActionPolicy.CANCEL,
      onLoadStop: (_, _) => _checkStatusProbe(),
    );
    try {
      await _statusProbe!.run().timeout(const Duration(seconds: 20));
      if (_finished) {
        await _statusProbe?.dispose();
        return;
      }
      _statusTimer = Timer.periodic(
        const Duration(seconds: 4),
        (_) => _checkStatusProbe(),
      );
    } catch (_) {
      // The visible page still provides a separate confirmation path.
      _statusTimer?.cancel();
    }
  }

  Future<void> _checkStatusProbe() async {
    if (!mounted || _finished || _statusBusy || !_submitted) return;
    final controller = _statusProbe?.webViewController;
    if (controller == null) return;
    _statusBusy = true;
    try {
      final uri = await controller.getUrl().timeout(const Duration(seconds: 8));
      if (!_trusted(uri)) return;
      final value = await controller
          .evaluateJavascript(
            source:
                '$_script\nwindow.IGCheckFacebook.step({submitted:true,images:[],uploaded:[]});',
          )
          .timeout(const Duration(seconds: 10));
      if (value is Map && value['state'] == 'review' && mounted && !_finished) {
        await _closeWithResult(
          InstagramVerifyResult(
            status: InstagramVerifyStatus.inReview,
            title: 'OK: Hồ sơ đang chờ xét duyệt',
            message: value['message'].toString(),
            userId: _uid,
          ),
        );
      }
    } catch (_) {
      /* Never turn a failed status check into a success. */
    } finally {
      _statusBusy = false;
    }
  }

  Future<void> _closeWithResult(InstagramVerifyResult result) async {
    if (_finished) return;
    _finished = true;
    _timer?.cancel();
    final cleaned = await _cleanSession();
    if (!mounted) return;
    final message = cleaned
        ? result.message
        : '${result.message}\nChưa dọn hết dữ liệu trình duyệt; hãy đóng phiên trước khi chạy lượt mới.';
    await context.read<NotificationService>().showLocalNotification(
      result.isSuccess ? 'Facebook: OK' : 'Facebook: lỗi',
      message,
      'facebook_verification',
    );
    if (!mounted) return;
    setState(() => _canPop = true);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Navigator.pop(
          context,
          InstagramVerifyResult(
            status: result.status,
            title: result.title,
            message: message,
            userId: result.userId,
          ),
        );
      }
    });
  }

  Future<void> _tick() async {
    if (!mounted || _paused || _busy || _finished) {
      return;
    }
    if (DateTime.now().difference(_lastProgress).inSeconds > 90) {
      _pause(
        _controller == null
            ? 'Trình duyệt Facebook chưa khởi tạo được. Đóng phiên này và thử lại; chưa gửi giấy tờ.'
            : _submitted
            ? 'Chưa thấy Facebook xác nhận. Kiểm tra trang bên dưới trước khi gửi lại.'
            : 'Chưa nhận diện được bước tiếp theo. Bạn có thể xử lý trên trang bên dưới.',
      );
      return;
    }
    if (_controller == null) return;
    _busy = true;
    try {
      final uri = await _controller!.getUrl().timeout(
        const Duration(seconds: 10),
      );
      if (uri == null || uri.toString() == 'about:blank') return;
      if (!_trusted(uri)) {
        _pause('Facebook chuyển sang trang ngoài luồng xác minh.');
        return;
      }
      if (uri.path.contains('/login') || uri.path.contains('login.php')) {
        _pause('Cookie hết hạn hoặc Facebook yêu cầu đăng nhập lại.');
        return;
      }
      Map<dynamic, dynamic>? result;
      if (_profileStage != 'done') {
        await _updateProfileStep();
        return;
      }
      if (!_triggered) {
        // Bootstrap the mobile Facebook session before running the supplied F12
        // request. Keep the returned mobile verification link in this WebView.
        if (uri.host != 'm.facebook.com' && uri.host != 'www.facebook.com') {
          _pause('Hãy mở phiên m.facebook.com trước khi lấy link xác minh.');
          return;
        }
        // Refuse to use a different account left over in the WebView session.
        final response = await _controller!
            .callAsyncJavaScript(
              functionBody:
                  '''
            $_script
            if (document.querySelector('input[type="password"]'))
              return {state:'expired',message:'Facebook đang hiện trang đăng nhập. Cookie chưa tạo được phiên hợp lệ hoặc đã hết hạn.'};
            try {
              const account = String(require('CurrentUserInitialData').ACCOUNT_ID || '');
              if (!account || account === '0')
                return {state:'expired',message:'Facebook chưa đăng nhập được bằng cookie này.'};
              if (account !== ${jsonEncode(_uid)})
                return {state:'blocked',message:'Phiên trình duyệt không khớp UID trong cookie.'};
            } catch (_) { return {state:'waiting',message:'Đang chờ phiên Facebook...'}; }
            return await window.IGCheckFacebook.trigger();
          ''',
            )
            .timeout(const Duration(seconds: 35));
        if (response?.error != null) {
          throw StateError('Không chạy được luồng F12.');
        }
        result = response?.value is Map ? response!.value as Map : null;
      } else {
        final args = jsonEncode({
          'images': _images,
          'documentType': widget.documentType,
          'uploaded': _uploaded.toList(),
          'submitted': _submitted,
        });
        final value = await _controller!
            .evaluateJavascript(
              source: '$_script\nwindow.IGCheckFacebook.step($args);',
            )
            .timeout(const Duration(seconds: 15));
        result = value is Map ? value : null;
      }
      if (!mounted || _finished || result == null) return;
      final state = result['state'];
      final message = result['message']?.toString() ?? 'Đang xử lý...';
      if (state == 'link') {
        final url = Uri.tryParse(result['url']?.toString() ?? '');
        if (!_trusted(url) ||
            url!.host != 'm.facebook.com' ||
            url.path != '/ixt/renderscreen/msite/') {
          throw StateError('Link xác minh không hợp lệ.');
        }
        _triggered = true;
        _verificationUrl = url.toString();
        _lastProgress = DateTime.now();
        await _enableMobileVerification().timeout(const Duration(seconds: 15));
        await _controller!.loadUrl(
          urlRequest: URLRequest(url: WebUri(url.toString())),
        );
      } else if (state == 'confirmed' || state == 'review') {
        await _closeWithResult(
          InstagramVerifyResult(
            status: InstagramVerifyStatus.inReview,
            title: 'Facebook đang xét duyệt',
            message: '$message Đây chưa phải kết quả cấp tích xanh.',
            userId: _uid,
          ),
        );
        return;
      } else if (state == 'blocked' || state == 'expired') {
        _pause(message);
        return;
      } else if (state == 'uploaded') {
        _uploaded = (result['uploaded'] as List).cast<int>().toSet();
        _lastProgress = DateTime.now();
      } else if (state == 'submitted') {
        _submitted = true;
        _lastProgress = DateTime.now();
        unawaited(_startStatusProbe());
      } else if (state == 'advance') {
        _lastProgress = DateTime.now();
      }
      setState(() => _message = message);
    } on TimeoutException {
      if (_triggered && _uploaded.length == _images.length) {
        _submitted = true;
      }
      _pause(
        'Trình duyệt Facebook không phản hồi trong thời gian chờ. Chưa có xác nhận tiếp nhận giấy tờ; không tự gửi lại.',
      );
    } catch (_) {
      // A navigation can interrupt evaluation after the page already clicked
      // Send. In that case only observe; never automatically send again.
      if (_triggered && _uploaded.length == _images.length) {
        _submitted = true;
      }
      _pause(
        'Không thể tiếp tục tự động. Kiểm tra trang Facebook bên dưới; chưa xác nhận hồ sơ đã được tiếp nhận.',
      );
    } finally {
      _busy = false;
    }
  }

  @override
  void dispose() {
    _finished = true;
    _timer?.cancel();
    _statusTimer?.cancel();
    // A newly opened verification must wait until this session is cleaned up,
    // including a preparation that was still running when the page was closed.
    _pendingCleanup = _preparation
        .then((_) => _cleanSession())
        .then((_) {})
        .catchError((_) {});
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: _canPop,
    onPopInvokedWithResult: (didPop, _) async {
      if (didPop || _finished) return;
      await _closeWithResult(
        InstagramVerifyResult(
          status: InstagramVerifyStatus.error,
          title: 'Đã kết thúc phiên',
          message: _submitted
              ? 'Đã nhấn gửi nhưng chưa xác nhận kết quả; kiểm tra trạng thái trước khi gửi lại.'
              : 'Đã dừng tác vụ trước khi có xác nhận gửi thành công.',
          userId: _uid,
        ),
      );
    },
    child: Scaffold(
      appBar: AppBar(title: const Text('Tự động xác minh Facebook')),
      body: SafeArea(
        child: Column(
          children: [
            Padding(padding: const EdgeInsets.all(12), child: Text(_message)),
            if (_paused && _controller != null)
              TextButton(
                onPressed: () => setState(() {
                  _paused = false;
                  _lastProgress = DateTime.now();
                }),
                child: const Text('Tiếp tục kiểm tra trang hiện tại'),
              ),
            if (_paused && _verificationUrl != null)
              TextButton.icon(
                onPressed: () async {
                  await Clipboard.setData(
                    ClipboardData(text: _verificationUrl!),
                  );
                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Đã sao chép link. Chỉ mở trong trình duyệt đăng nhập đúng tài khoản Facebook này.',
                        ),
                      ),
                    );
                  }
                },
                icon: const Icon(Icons.copy),
                label: const Text('Sao chép link xác minh để kiểm tra'),
              ),
            Expanded(
              child: Align(
                alignment: Alignment.topCenter,
                child: ConstrainedBox(
                  constraints: BoxConstraints(
                    maxWidth: _mobileMode ? 400 : double.infinity,
                  ),
                  child: _loading
                      ? Center(
                          child: _paused
                              ? const Icon(Icons.error_outline)
                              : const CircularProgressIndicator(),
                        )
                      : InAppWebView(
                          initialUrlRequest: URLRequest(
                            url: WebUri('https://m.facebook.com/'),
                          ),
                          initialSettings: InAppWebViewSettings(
                            javaScriptEnabled: true,
                            domStorageEnabled: true,
                            useShouldOverrideUrlLoading: true,
                            userAgent: _mobileMode
                                ? _mobileUserAgent
                                : _desktopUserAgent,
                            preferredContentMode: _mobileMode
                                ? UserPreferredContentMode.MOBILE
                                : UserPreferredContentMode.RECOMMENDED,
                          ),
                          onWebViewCreated: (controller) {
                            _controller = controller;
                            if (mounted && !_paused) {
                              setState(
                                () => _message =
                                    'Đã khởi tạo trình duyệt, đang tải m.facebook.com...',
                              );
                            }
                          },
                          shouldOverrideUrlLoading: (_, action) async {
                            if (action.isForMainFrame &&
                                !_trusted(action.request.url) &&
                                !(_cleaning &&
                                    action.request.url?.toString() ==
                                        'about:blank')) {
                              _pause('Đã dừng chuyển hướng ra ngoài Facebook.');
                              return NavigationActionPolicy.CANCEL;
                            }
                            return NavigationActionPolicy.ALLOW;
                          },
                          onLoadStop: (_, _) => _tick(),
                          onReceivedError: (_, request, error) {
                            if (request.isForMainFrame == true) {
                              _pause(
                                'Không tải được trang Facebook (${error.type}): ${error.description}',
                              );
                            }
                          },
                          onReceivedHttpError: (_, request, response) {
                            if (request.isForMainFrame == true) {
                              _pause(
                                'Facebook trả lỗi HTTP ${response.statusCode}. Kiểm tra cookie và trang đang mở.',
                              );
                            }
                          },
                        ),
                ),
              ),
            ),
          ],
        ),
      ),
    ),
  );
}
