import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../widgets/app_button.dart';
import '../../widgets/app_text_field.dart';
import '../../utils/account_parser_helper.dart';
import '../../services/meta_checker_service.dart';

class CookieFacebookToolScreen extends StatefulWidget {
  const CookieFacebookToolScreen({super.key});

  @override
  State<CookieFacebookToolScreen> createState() => _CookieFacebookToolScreenState();
}

class _CookieFacebookToolScreenState extends State<CookieFacebookToolScreen> {
  final _cookieController = TextEditingController();
  final _proxyController = TextEditingController();
  bool _isLoading = false;
  bool _isCheckingMeta = false;
  bool _isInitialized = false;
  String? _resultLink;
  String? _errorMessage;
  MetaVerifiedCheckResult? _metaResult;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_isInitialized) {
      final args = ModalRoute.of(context)?.settings.arguments;
      if (args is String && args.isNotEmpty) {
        _cookieController.text = args;
      }
      _isInitialized = true;
    }
  }

  @override
  void dispose() {
    _cookieController.dispose();
    _proxyController.dispose();
    super.dispose();
  }

  Future<void> _checkMetaVerified() async {
    final cookie = _cookieController.text.trim();
    if (cookie.isEmpty) {
      setState(() {
        _errorMessage = 'Vui lòng nhập cookie Facebook để kiểm tra Meta Verified.';
        _metaResult = null;
      });
      return;
    }

    setState(() {
      _isCheckingMeta = true;
      _errorMessage = null;
      _metaResult = null;
    });

    try {
      final proxy = _proxyController.text.trim();
      final result = await MetaCheckerService.checkMetaVerifiedStatus(
        cookie: cookie,
        proxy: proxy.isNotEmpty ? proxy : null,
      );
      setState(() {
        _metaResult = result;
        _isCheckingMeta = false;
      });
    } catch (e) {
      setState(() {
        _errorMessage = 'Lỗi kiểm tra Meta Verified: $e';
        _isCheckingMeta = false;
      });
    }
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

      final proxy = _proxyController.text.trim();
      if (proxy.isNotEmpty) {
        MetaCheckerService.applyProxy(dio, proxy);
      }

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

  Future<void> _pasteFromClipboard() async {
    final data = await Clipboard.getData('text/plain');
    if (!mounted) return;
    final text = data?.text?.trim() ?? '';
    if (text.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Bộ nhớ tạm đang trống.')),
      );
      return;
    }

    final extracted = AccountParserHelper.extractCookieOnly(text) ?? text;
    setState(() {
      _cookieController.text = extracted;
      _errorMessage = null;
      _resultLink = null;
    });

    if (extracted != text) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã tự động trích xuất Cookie từ bộ nhớ tạm!')),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Đã dán Cookie từ bộ nhớ tạm!')),
      );
    }
  }

  Future<void> _promptImportFromNotepad() async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_download_outlined, color: Colors.blue),
            SizedBox(width: 8),
            Text('Nhập từ note.2fa.live', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dán link Notepad hoặc mã alias (ví dụ: note.2fa.live/abcxyz hoặc abcxyz):',
              style: TextStyle(fontSize: 13, color: Colors.black87),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: textController,
              autofocus: true,
              decoration: InputDecoration(
                hintText: 'https://note.2fa.live/note/...',
                filled: true,
                fillColor: const Color(0xFFF2F2F7),
                border: OutlineInputBorder(borderRadius: BorderRadius.circular(8), borderSide: BorderSide.none),
                contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Hủy'),
          ),
          ElevatedButton(
            onPressed: () {
              final val = textController.text.trim();
              if (val.isNotEmpty) {
                Navigator.pop(ctx, val);
              }
            },
            child: const Text('Tải về'),
          ),
        ],
      ),
    );

    if (result != null && result.isNotEmpty) {
      _loadNotepadAndSelectCookie(result);
    }
  }

  String? _parseNotepadAlias(String input) {
    final clean = input.trim();
    if (clean.isEmpty) return null;
    if (!clean.contains('/') && !clean.contains('.')) return clean;
    try {
      final uri = Uri.parse(clean.startsWith('http') ? clean : 'https://$clean');
      final segs = uri.pathSegments;
      if (segs.contains('note') && segs.indexOf('note') < segs.length - 1) {
        return segs[segs.indexOf('note') + 1];
      } else if (segs.isNotEmpty) {
        return segs.last;
      }
    } catch (_) {}
    return null;
  }

  Future<void> _loadNotepadAndSelectCookie(String input) async {
    final alias = _parseNotepadAlias(input) ?? input;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(width: 20),
            Expanded(child: Text('Đang tải danh sách từ Notepad...')),
          ],
        ),
      ),
    );

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      final response = await dio.get('https://note.2fa.live/note/$alias');

      if (mounted) Navigator.pop(context); // Close loading dialog

      final data = response.data;
      String? rawContent;
      if (data is Map) {
        rawContent = data['r']?.toString();
      } else if (data is String) {
        final decoded = json.decode(data);
        rawContent = decoded['r']?.toString();
      }

      if (rawContent == null || rawContent.trim().isEmpty) {
        throw Exception('Không có dữ liệu trong Notepad.');
      }

      final parsed = AccountParserHelper.parseMultipleLines(rawContent);
      if (parsed.isEmpty) {
        throw Exception('Không tìm thấy dòng tài khoản hoặc Cookie nào trong Notepad.');
      }

      final accountsWithCookie = parsed.where((a) => a.hasCookie).toList();
      if (accountsWithCookie.isEmpty) {
        throw Exception('Các dòng tài khoản trong Notepad này không chứa Cookie Facebook nào.');
      }

      if (accountsWithCookie.length == 1) {
        final chosen = accountsWithCookie.first;
        setState(() {
          _cookieController.text = chosen.cookie;
          _errorMessage = null;
          _resultLink = null;
        });
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Đã chọn Cookie của ${chosen.username.isNotEmpty ? chosen.username : "tài khoản"}!'),
            ),
          );
        }
      } else {
        if (mounted) {
          _showCookieSelectionBottomSheet(accountsWithCookie);
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context); // Close loading dialog if still open
      final msg = e.toString().replaceAll('Exception: ', '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải Notepad: $msg'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _showCookieSelectionBottomSheet(List<ParsedAccount> accounts) {
    showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.all(16.0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Chọn Cookie Facebook muốn kiểm tra',
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Color(0xFF1C1C1E)),
                    ),
                    Text(
                      '${accounts.length} cookie',
                      style: const TextStyle(fontSize: 13, color: Colors.grey, fontWeight: FontWeight.w500),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: ListView.builder(
                  itemCount: accounts.length,
                  itemBuilder: (context, index) {
                    final acc = accounts[index];
                    final label = acc.username.isNotEmpty ? acc.username : 'Cookie #${index + 1}';
                    return ListTile(
                      leading: const CircleAvatar(
                        backgroundColor: Color(0xFFFFF3E0),
                        child: Icon(Icons.cookie, color: Colors.deepOrange),
                      ),
                      title: Text(label, style: const TextStyle(fontWeight: FontWeight.bold)),
                      subtitle: Text(
                        acc.cookie.length > 50 ? '${acc.cookie.substring(0, 50)}...' : acc.cookie,
                        style: const TextStyle(fontSize: 12, color: Colors.grey),
                        overflow: TextOverflow.ellipsis,
                      ),
                      onTap: () {
                        setState(() {
                          _cookieController.text = acc.cookie;
                          _errorMessage = null;
                          _resultLink = null;
                        });
                        Navigator.pop(ctx);
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text('Đã chọn Cookie của $label!')),
                        );
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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

                // Cookie Input Field with Quick Actions
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cookie Facebook',
                      style: TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF1C1C1E),
                      ),
                    ),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        TextButton.icon(
                          onPressed: _pasteFromClipboard,
                          icon: const Icon(Icons.paste_rounded, size: 15),
                          label: const Text('Dán & Tách', style: TextStyle(fontSize: 12)),
                          style: TextButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                          ),
                        ),
                        const SizedBox(width: 6),
                        OutlinedButton.icon(
                          onPressed: _promptImportFromNotepad,
                          icon: const Icon(Icons.cloud_download_outlined, size: 15),
                          label: const Text('note.2fa.live', style: TextStyle(fontSize: 12)),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                            minimumSize: Size.zero,
                            tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                            side: const BorderSide(color: Colors.blue),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 6),
                AppTextField(
                  controller: _cookieController,
                  labelText: '',
                  hintText: 'Nhập/dán Cookie Facebook (hỗ trợ tự tách từ dòng UID|PASS|2FA|COOKIE)...',
                  maxLines: 5,
                  prefixIcon: Icons.cookie_outlined,
                  onChanged: (val) {
                    if (val.contains('|') || val.contains('\t')) {
                      final extracted = AccountParserHelper.extractCookieOnly(val);
                      if (extracted != null && extracted.isNotEmpty && extracted != val) {
                        _cookieController.text = extracted;
                        _cookieController.selection = TextSelection.fromPosition(
                          TextPosition(offset: extracted.length),
                        );
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Đã tự động trích xuất chuỗi Cookie từ dòng tài khoản!'),
                            duration: Duration(seconds: 1),
                          ),
                        );
                      }
                    }
                  },
                ),
                const SizedBox(height: 12),
                AppTextField(
                  controller: _proxyController,
                  labelText: 'Proxy (Tùy chọn)',
                  hintText: 'IP:Port hoặc IP:Port:User:Pass (chỉ áp dụng riêng cho tab này)',
                  prefixIcon: Icons.shield_outlined,
                  suffixIcon: ValueListenableBuilder<TextEditingValue>(
                    valueListenable: _proxyController,
                    builder: (context, value, child) {
                      if (value.text.isEmpty) return const SizedBox.shrink();
                      return IconButton(
                        icon: const Icon(Icons.clear, size: 18),
                        onPressed: () => _proxyController.clear(),
                      );
                    },
                  ),
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
                        onPressed: (_isLoading || _isCheckingMeta)
                            ? null
                            : () {
                                _cookieController.clear();
                                _proxyController.clear();
                                setState(() {
                                  _resultLink = null;
                                  _errorMessage = null;
                                  _metaResult = null;
                                });
                              },
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: AppButton(
                        text: 'Get Link Checkpoint',
                        icon: Icons.link,
                        isLoading: _isLoading,
                        onPressed: _isCheckingMeta ? null : _extractLink,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 10),
                AppButton(
                  text: 'Kiểm tra Meta Verified',
                  icon: Icons.verified_outlined,
                  type: AppButtonType.secondary,
                  isLoading: _isCheckingMeta,
                  onPressed: _isLoading ? null : _checkMetaVerified,
                ),
                const SizedBox(height: 20),

                // Meta Verified Result Card
                if (_metaResult != null) ...[
                  Card(
                    elevation: 0,
                    color: _metaResult!.type == MetaVerifiedStatusType.pending
                        ? const Color(0xFFFFF8E1)
                        : _metaResult!.type == MetaVerifiedStatusType.needed
                            ? const Color(0xFFFFEBEE)
                            : _metaResult!.type == MetaVerifiedStatusType.active
                                ? const Color(0xFFE8F8F5)
                                : const Color(0xFFF5F5F7),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(16),
                      side: BorderSide(
                        color: _metaResult!.type == MetaVerifiedStatusType.pending
                            ? Colors.amber.shade400
                            : _metaResult!.type == MetaVerifiedStatusType.needed
                                ? Colors.red.shade300
                                : _metaResult!.type == MetaVerifiedStatusType.active
                                    ? Colors.teal.shade300
                                    : Colors.grey.shade400,
                        width: 1,
                      ),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Row(
                            children: [
                              Icon(
                                _metaResult!.type == MetaVerifiedStatusType.pending
                                    ? Icons.hourglass_top_rounded
                                    : _metaResult!.type == MetaVerifiedStatusType.needed
                                        ? Icons.warning_amber_rounded
                                        : _metaResult!.type == MetaVerifiedStatusType.active
                                            ? Icons.verified_rounded
                                            : Icons.info_outline,
                                color: _metaResult!.type == MetaVerifiedStatusType.pending
                                    ? Colors.amber.shade800
                                    : _metaResult!.type == MetaVerifiedStatusType.needed
                                        ? Colors.red.shade700
                                        : _metaResult!.type == MetaVerifiedStatusType.active
                                            ? Colors.teal.shade700
                                            : Colors.grey.shade700,
                                size: 22,
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'Meta Verified: ${_metaResult!.statusText}',
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: _metaResult!.type == MetaVerifiedStatusType.pending
                                        ? Colors.amber.shade900
                                        : _metaResult!.type == MetaVerifiedStatusType.needed
                                            ? Colors.red.shade800
                                            : _metaResult!.type == MetaVerifiedStatusType.active
                                                ? Colors.teal.shade900
                                                : Colors.grey.shade800,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 10),
                          Text(
                            _metaResult!.type == MetaVerifiedStatusType.pending
                                ? 'Trạng thái: Verification pending (Đang trong hàng đợi xét duyệt danh tính)'
                                : _metaResult!.type == MetaVerifiedStatusType.needed
                                    ? 'Trạng thái: Verification needed (Cần tải lại giấy tờ tùy thân CCCD)'
                                    : _metaResult!.type == MetaVerifiedStatusType.active
                                        ? 'Trạng thái: Đang hoạt động (Active)'
                                        : 'Trạng thái: ${_metaResult!.message}',
                            style: const TextStyle(fontSize: 13, height: 1.4, color: Colors.black87),
                          ),
                          const SizedBox(height: 12),
                          OutlinedButton.icon(
                            icon: const Icon(Icons.open_in_new, size: 16),
                            label: const Text('Mở trang Subscriptions Facebook'),
                            onPressed: () async {
                              final uri = Uri.parse('https://accountscenter.facebook.com/subscriptions');
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                ],

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
