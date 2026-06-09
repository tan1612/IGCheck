import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';

class CookieFacebookToolScreen extends StatefulWidget {
  const CookieFacebookToolScreen({super.key});

  @override
  State<CookieFacebookToolScreen> createState() => _CookieFacebookToolScreenState();
}

class _CookieFacebookToolScreenState extends State<CookieFacebookToolScreen> {
  final _cookieController = TextEditingController();
  bool _isLoading = false;
  String? _resultLink;
  String? _errorMessage;

  @override
  void dispose() {
    _cookieController.dispose();
    super.dispose();
  }

  Future<void> _extractLink() async {
    final cookie = _cookieController.text.trim();
    if (cookie.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng nhập cookie Facebook.';
        _resultLink = null;
      });
      return;
    }

    setState(() {
      _isLoading = true;
      _errorMessage = null;
      _resultLink = null;
    });

    try {
      final dio = Dio(BaseOptions(
        connectTimeout: const Duration(seconds: 15),
        receiveTimeout: const Duration(seconds: 15),
        validateStatus: (status) => status != null && status < 500,
      ));

      final headers = {
        'cookie': cookie,
        'user-agent': 'Mozilla/5.0 (iPhone; CPU iPhone OS 16_6 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/16.6 Mobile/15E148 Safari/604.1',
        'accept': 'text/html,application/xhtml+xml,application/xml;q=0.9,image/webp,*/*;q=0.8',
        'accept-language': 'vi-VN,vi;q=0.9,en-US;q=0.8,en;q=0.7',
      };

      final response = await dio.get(
        'https://m.facebook.com/',
        options: Options(
          headers: headers,
          followRedirects: true,
          maxRedirects: 5,
        ),
      );

      final finalUrl = response.realUri.toString();
      final htmlBody = response.data?.toString() ?? '';

      // Check if the final URL is a checkpoint link
      if (finalUrl.contains('serialized_state') || 
          finalUrl.contains('renderscreen/msite') || 
          finalUrl.contains('/checkpoint/')) {
        setState(() {
          _resultLink = finalUrl;
          _isLoading = false;
        });
        return;
      }

      // Fallback: Check HTML body for serialized_state links using Regex
      final regexes = [
        RegExp(r'''https?://[a-zA-Z0-9\.]*facebook\.com/ixt/renderscreen/msite/\?serialized_state=[^"'\s<>]+'''),
        RegExp(r'''/ixt/renderscreen/msite/\?serialized_state=[^"'\s<>]+'''),
        RegExp(r'''https?://[a-zA-Z0-9\.]*facebook\.com/checkpoint/[^"'\s<>]+'''),
        RegExp(r'''/checkpoint/[^"'\s<>]+'''),
      ];

      for (final reg in regexes) {
        final match = reg.firstMatch(htmlBody);
        if (match != null) {
          String matchedUrl = match.group(0)!;
          // Decode html entities if any (like &amp; to &)
          matchedUrl = matchedUrl.replaceAll('&amp;', '&');
          if (matchedUrl.startsWith('/')) {
            matchedUrl = 'https://m.facebook.com$matchedUrl';
          }
          setState(() {
            _resultLink = matchedUrl;
            _isLoading = false;
          });
          return;
        }
      }

      // Check if redirecting to login page or contains login form elements -> Expired/Invalid Cookie
      if (finalUrl.contains('/login') || 
          finalUrl.contains('login.php') || 
          htmlBody.contains('name="login"') || 
          htmlBody.contains('id="login_form"') ||
          htmlBody.contains('/login/device-based/')) {
        setState(() {
          _errorMessage = 'Cookie đã hết hạn hoặc không hợp lệ. Vui lòng đăng nhập lại và lấy cookie mới.';
          _isLoading = false;
        });
        return;
      }

      // Check if normal feed page or active session -> Active Cookie (Not Checkpointed)
      if (finalUrl.contains('home.php') || 
          finalUrl.contains('/feed') || 
          htmlBody.contains('mbasic_logout_button') || 
          htmlBody.contains('composer') || 
          htmlBody.contains('c_user') ||
          finalUrl == 'https://m.facebook.com/' ||
          finalUrl == 'https://m.facebook.com') {
        setState(() {
          _errorMessage = 'Tài khoản đang hoạt động bình thường, không bị khóa hoặc checkpoint.';
          _isLoading = false;
        });
        return;
      }

      // Default fallback error
      setState(() {
        _errorMessage = 'Không tìm thấy link checkpoint từ cookie này.\nCó thể tài khoản không bị khóa hoặc cookie không đúng định dạng.';
        _isLoading = false;
      });

    } catch (e) {
      setState(() {
        _errorMessage = 'Lỗi kết nối hoặc xử lý cookie: $e';
        _isLoading = false;
      });
    }
  }

  Future<void> _copyToClipboard() async {
    if (_resultLink != null) {
      await Clipboard.setData(ClipboardData(text: _resultLink!));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Đã sao chép link xác minh vào bộ nhớ tạm'),
            behavior: SnackBarBehavior.floating,
          ),
        );
      }
    }
  }

  Future<void> _openInBrowser() async {
    if (_resultLink != null) {
      final uri = Uri.parse(_resultLink!);
      try {
        if (await canLaunchUrl(uri)) {
          await launchUrl(uri, mode: LaunchMode.externalApplication);
        } else {
          throw 'Không thể mở trình duyệt';
        }
      } catch (e) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Không thể mở liên kết: $e'),
              behavior: SnackBarBehavior.floating,
            ),
          );
        }
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const Text('Công cụ Facebook'),
        elevation: 0,
      ),
      body: GestureDetector(
        onTap: () => FocusScope.of(context).unfocus(),
        behavior: HitTestBehavior.opaque,
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Instruction Box
                Card(
                  elevation: 0,
                  color: theme.primaryColor.withValues(alpha: 0.05),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(16),
                    side: BorderSide(color: theme.primaryColor.withValues(alpha: 0.1), width: 1),
                  ),
                  child: Padding(
                    padding: const EdgeInsets.all(16.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.info_outline, color: theme.primaryColor, size: 20),
                            const SizedBox(width: 8),
                            Text(
                              'Hướng dẫn trích xuất link checkpoint',
                              style: TextStyle(
                                fontSize: 15,
                                fontWeight: FontWeight.bold,
                                color: theme.primaryColor,
                              ),
                            ),
                          ],
                        ),
                        const Divider(height: 20, thickness: 0.5),
                        const Text(
                          '1. Đăng nhập tài khoản Facebook trên trình duyệt.\n'
                          '2. Sao chép toàn bộ Cookie Facebook của tài khoản (dạng datr=...; sb=...; c_user=...).\n'
                          '3. Dán Cookie vào ô nhập bên dưới và nhấn "Get Link".\n'
                          '4. Hệ thống sẽ trích xuất và hiển thị link xác minh danh tính.',
                          style: TextStyle(
                            fontSize: 13,
                            color: Color(0xFF555555),
                            height: 1.5,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 20),

                // Cookie Input Field
                AppTextField(
                  controller: _cookieController,
                  labelText: 'Cookie Facebook',
                  hintText: 'Nhập hoặc dán Cookie Facebook tại đây...',
                  maxLines: 5,
                  prefixIcon: Icons.cookie_outlined,
                ),
                const SizedBox(height: 20),

                // Action Buttons
                Row(
                  children: [
                    Expanded(
                      child: AppButton(
                        text: 'Xóa',
                        type: AppButtonType.outline,
                        icon: Icons.delete_outline,
                        onPressed: _isLoading
                            ? null
                            : () {
                                _cookieController.clear();
                                setState(() {
                                  _resultLink = null;
                                  _errorMessage = null;
                                });
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        text: 'Get Link',
                        icon: Icons.link,
                        isLoading: _isLoading,
                        onPressed: _extractLink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 24),

                // Success Result Card
                if (_resultLink != null) ...[
                  Card(
                    elevation: 0,
                    color: const Color(0xFFE8F8F5), // Light soft green
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFA3E4D7), width: 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          const Row(
                            children: [
                              Icon(Icons.check_circle_outline, color: Color(0xFF117A65), size: 22),
                              SizedBox(width: 8),
                              Text(
                                'Trích xuất thành công!',
                                style: TextStyle(
                                  fontSize: 15,
                                  fontWeight: FontWeight.bold,
                                  color: Color(0xFF117A65),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 12),
                          Container(
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.white,
                              borderRadius: BorderRadius.circular(12),
                              border: Border.all(color: const Color(0xFFD5F5E3)),
                            ),
                            child: Text(
                              _resultLink!,
                              style: const TextStyle(
                                fontSize: 13,
                                color: Color(0xFF2C3E50),
                                fontFamily: 'monospace',
                              ),
                            ),
                          ),
                          const SizedBox(height: 16),
                          Row(
                            children: [
                              Expanded(
                                child: AppButton(
                                  text: 'Sao chép',
                                  type: AppButtonType.secondary,
                                  icon: Icons.copy,
                                  onPressed: _copyToClipboard,
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: AppButton(
                                  text: 'Mở link',
                                  icon: Icons.launch,
                                  onPressed: _openInBrowser,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                  ),
                ],

                // Error Card
                if (_errorMessage != null) ...[
                  Card(
                    elevation: 0,
                    color: const Color(0xFFFFEBEE), // Light soft red
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: const BorderSide(color: Color(0xFFFFCDD2), width: 1),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          const Icon(Icons.error_outline, color: Color(0xFFFF3B30), size: 22),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'Thông báo',
                                  style: TextStyle(
                                    fontSize: 14,
                                    fontWeight: FontWeight.bold,
                                    color: Color(0xFFFF3B30),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  _errorMessage!,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    color: Color(0xFF5D4037),
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
