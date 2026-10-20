import 'dart:convert';
import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_picker/image_picker.dart';
import 'package:dio/dio.dart';
import 'package:url_launcher/url_launcher.dart';
import '../../services/instagram_verification_service.dart';
import '../../utils/account_parser_helper.dart';

class InstagramCookieVerifyScreen extends StatefulWidget {
  final bool isTab;
  const InstagramCookieVerifyScreen({super.key, this.isTab = false});

  @override
  State<InstagramCookieVerifyScreen> createState() => _InstagramCookieVerifyScreenState();
}

class _InstagramCookieVerifyScreenState extends State<InstagramCookieVerifyScreen> {
  final _cookieController = TextEditingController();
  final _proxyController = TextEditingController();
  final _customEndpointController = TextEditingController();
  final _picker = ImagePicker();

  int _photoCount = 1; // 1 or 2
  Uint8List? _frontImageBytes;
  Uint8List? _backImageBytes;

  bool _isLoading = false;
  String? _progressMessage;
  InstagramVerifyResult? _verifyResult;
  bool _showAdvanced = false;

  @override
  void dispose() {
    _cookieController.dispose();
    _proxyController.dispose();
    _customEndpointController.dispose();
    super.dispose();
  }

  Future<void> _pickImage(bool isFront) async {
    showCupertinoModalPopup(
      context: context,
      builder: (ctx) => CupertinoActionSheet(
        title: Text(isFront ? 'Chọn ảnh giấy tờ (Mặt trước)' : 'Chọn ảnh giấy tờ (Mặt sau)'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _getImageFromSource(ImageSource.camera, isFront);
            },
            child: const Text('Chụp ảnh từ Camera'),
          ),
          CupertinoActionSheetAction(
            onPressed: () {
              Navigator.pop(ctx);
              _getImageFromSource(ImageSource.gallery, isFront);
            },
            child: const Text('Chọn ảnh từ Thư viện'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.pop(ctx),
          isDestructiveAction: true,
          child: const Text('Hủy'),
        ),
      ),
    );
  }

  Future<void> _getImageFromSource(ImageSource source, bool isFront) async {
    try {
      final picked = await _picker.pickImage(
        source: source,
        maxWidth: 2000,
        maxHeight: 2000,
        imageQuality: 90,
      );
      if (picked != null) {
        final bytes = await picked.readAsBytes();
        setState(() {
          if (isFront) {
            _frontImageBytes = bytes;
          } else {
            _backImageBytes = bytes;
          }
          _verifyResult = null;
        });
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi chọn ảnh: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  void _removeImage(bool isFront) {
    setState(() {
      if (isFront) {
        _frontImageBytes = null;
      } else {
        _backImageBytes = null;
      }
    });
  }

  Future<void> _pasteCookie() async {
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
      _verifyResult = null;
    });

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(extracted != text ? 'Đã tự động trích xuất Cookie từ bộ nhớ tạm!' : 'Đã dán Cookie!'),
      ),
    );
  }

  Future<void> _importFromNotepad() async {
    final textController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.cloud_download_outlined, color: Color(0xFFD946EF)),
            SizedBox(width: 8),
            Text('Nhập từ note.2fa.live', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Dán link Notepad hoặc mã alias (ví dụ: note.2fa.live/instagram hoặc abcxyz):',
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
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFD946EF),
              foregroundColor: Colors.white,
            ),
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
      _loadNotepadAndExtractCookie(result);
    }
  }

  Future<void> _loadNotepadAndExtractCookie(String input) async {
    String alias = input.trim();
    if (alias.contains('/')) {
      try {
        final uri = Uri.parse(alias.startsWith('http') ? alias : 'https://$alias');
        alias = uri.pathSegments.isNotEmpty ? uri.pathSegments.last : alias;
      } catch (_) {}
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Color(0xFFD946EF)),
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

      if (mounted) Navigator.pop(context);

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
      final accountsWithCookie = parsed.where((a) => a.hasCookie).toList();

      if (accountsWithCookie.isEmpty) {
        throw Exception('Không tìm thấy dòng tài khoản nào chứa Cookie trong Notepad.');
      }

      setState(() {
        _cookieController.text = accountsWithCookie.first.cookie;
        _verifyResult = null;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Đã nạp Cookie của ${accountsWithCookie.first.username.isNotEmpty ? accountsWithCookie.first.username : "tài khoản"}!'),
          ),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Lỗi tải Notepad: $e'), backgroundColor: Colors.red),
        );
      }
    }
  }

  Future<void> _startVerification() async {
    final cookie = _cookieController.text.trim();
    if (cookie.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng nhập Cookie Instagram!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_frontImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Vui lòng tải lên ít nhất 1 ảnh giấy tờ tùy thân!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (_photoCount == 2 && _backImageBytes == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Bạn đã chọn 2 ảnh, vui lòng tải lên thêm ảnh mặt sau!'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() {
      _isLoading = true;
      _progressMessage = 'Bắt đầu quy trình xác minh...';
      _verifyResult = null;
    });

    final images = <Uint8List>[_frontImageBytes!];
    if (_photoCount == 2 && _backImageBytes != null) {
      images.add(_backImageBytes!);
    }

    final proxy = _proxyController.text.trim();
    final customEndpoint = _customEndpointController.text.trim();

    final result = await InstagramVerificationService.submitVerification(
      cookie: cookie,
      documentImages: images,
      proxy: proxy.isNotEmpty ? proxy : null,
      customEndpoint: customEndpoint.isNotEmpty ? customEndpoint : null,
      onProgress: (msg) {
        if (mounted) {
          setState(() {
            _progressMessage = msg;
          });
        }
      },
    );

    if (mounted) {
      setState(() {
        _verifyResult = result;
        _isLoading = false;
        _progressMessage = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final cardContent = SingleChildScrollView(
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // MAIN CARD CONTAINER (Matching user's reference image)
          Container(
            decoration: BoxDecoration(
              color: Colors.white,
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: const Color(0xFFE5E7EB), width: 1),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.03),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
              ],
            ),
            padding: const EdgeInsets.all(18.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // 1. Header: Icon + Title
                Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.all(6),
                      decoration: BoxDecoration(
                        gradient: const LinearGradient(
                          colors: [Color(0xFFF43F5E), Color(0xFFD946EF)],
                          begin: Alignment.topLeft,
                          end: Alignment.bottomRight,
                        ),
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: const Icon(
                        Icons.verified_user_rounded,
                        color: Colors.white,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    const Text(
                      'Thông tin xác minh',
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1F2937),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 2. Cookie Instagram Section
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Cookie Instagram',
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF374151),
                      ),
                    ),
                    Row(
                      children: [
                        InkWell(
                          onTap: _pasteCookie,
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.paste_rounded, size: 14, color: Color(0xFFD946EF)),
                                SizedBox(width: 4),
                                Text(
                                  'Dán',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFFD946EF),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        InkWell(
                          onTap: _importFromNotepad,
                          borderRadius: BorderRadius.circular(6),
                          child: const Padding(
                            padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                            child: Row(
                              children: [
                                Icon(Icons.cloud_download_outlined, size: 14, color: Color(0xFF2563EB)),
                                SizedBox(width: 4),
                                Text(
                                  'Note 2FA',
                                  style: TextStyle(
                                    fontSize: 12,
                                    fontWeight: FontWeight.w600,
                                    color: Color(0xFF2563EB),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        if (_cookieController.text.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          InkWell(
                            onTap: () {
                              setState(() {
                                _cookieController.clear();
                              });
                            },
                            child: const Padding(
                              padding: EdgeInsets.symmetric(horizontal: 4, vertical: 2),
                              child: Text(
                                'Xóa',
                                style: TextStyle(fontSize: 12, color: Colors.grey),
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: const Color(0xFFD1D5DB)),
                  ),
                  child: TextField(
                    controller: _cookieController,
                    maxLines: 4,
                    minLines: 3,
                    style: const TextStyle(fontSize: 13, fontFamily: 'monospace'),
                    decoration: const InputDecoration(
                      hintText: 'datr=...; ig_did=...; mid=...; csrftoken=...; ds_user_id=...; sessionid=...',
                      hintStyle: TextStyle(fontSize: 12, color: Color(0xFF9CA3AF)),
                      contentPadding: EdgeInsets.all(12),
                      border: InputBorder.none,
                    ),
                    onChanged: (_) => setState(() {}),
                  ),
                ),
                const SizedBox(height: 18),

                // 3. Số lượng ảnh Section (Segmented 1 ảnh / 2 ảnh)
                const Text(
                  'Số lượng ảnh',
                  style: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    // Option 1: 1 ảnh
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _photoCount = 1;
                          });
                        },
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: _photoCount == 1 ? const Color(0xFFFDF2F8) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _photoCount == 1 ? const Color(0xFFE1306C) : const Color(0xFFD1D5DB),
                              width: _photoCount == 1 ? 1.5 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '1 ảnh',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _photoCount == 1 ? const Color(0xFFE1306C) : const Color(0xFF4B5563),
                            ),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    // Option 2: 2 ảnh
                    Expanded(
                      child: GestureDetector(
                        onTap: () {
                          setState(() {
                            _photoCount = 2;
                          });
                        },
                        child: Container(
                          height: 42,
                          decoration: BoxDecoration(
                            color: _photoCount == 2 ? const Color(0xFFFDF2F8) : Colors.white,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: _photoCount == 2 ? const Color(0xFFE1306C) : const Color(0xFFD1D5DB),
                              width: _photoCount == 2 ? 1.5 : 1,
                            ),
                          ),
                          alignment: Alignment.center,
                          child: Text(
                            '2 ảnh',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w600,
                              color: _photoCount == 2 ? const Color(0xFFE1306C) : const Color(0xFF4B5563),
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 18),

                // 4. Ảnh giấy tờ Section
                Text(
                  _photoCount == 1 ? 'Ảnh giấy tờ' : 'Ảnh giấy tờ (Mặt trước & Mặt sau)',
                  style: const TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.w600,
                    color: Color(0xFF374151),
                  ),
                ),
                const SizedBox(height: 8),

                if (_photoCount == 1)
                  _buildPhotoContainer(
                    bytes: _frontImageBytes,
                    label: 'Chọn ảnh giấy tờ (CCCD / Bằng lái / Hộ chiếu)',
                    onPick: () => _pickImage(true),
                    onRemove: () => _removeImage(true),
                  )
                else ...[
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mặt trước',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF6B7280)),
                            ),
                            const SizedBox(height: 4),
                            _buildPhotoContainer(
                              bytes: _frontImageBytes,
                              label: '+ Ảnh mặt trước',
                              height: 140,
                              onPick: () => _pickImage(true),
                              onRemove: () => _removeImage(true),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text(
                              'Mặt sau',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.w500, color: Color(0xFF6B7280)),
                            ),
                            const SizedBox(height: 4),
                            _buildPhotoContainer(
                              bytes: _backImageBytes,
                              label: '+ Ảnh mặt sau',
                              height: 140,
                              onPick: () => _pickImage(false),
                              onRemove: () => _removeImage(false),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],

                const SizedBox(height: 14),

                // 5. Cài đặt nâng cao (Proxy & Custom Endpoint)
                Theme(
                  data: Theme.of(context).copyWith(dividerColor: Colors.transparent),
                  child: ExpansionTile(
                    tilePadding: EdgeInsets.zero,
                    title: Row(
                      children: [
                        Icon(
                          _showAdvanced ? Icons.tune_rounded : Icons.tune_outlined,
                          size: 16,
                          color: const Color(0xFF6B7280),
                        ),
                        const SizedBox(width: 6),
                        const Text(
                          'Cấu hình nâng cao (Proxy / Server riêng)',
                          style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Color(0xFF6B7280)),
                        ),
                      ],
                    ),
                    onExpansionChanged: (val) {
                      setState(() {
                        _showAdvanced = val;
                      });
                    },
                    children: [
                      const SizedBox(height: 4),
                      TextField(
                        controller: _proxyController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Proxy (tùy chọn: IP:Port hoặc IP:Port:User:Pass)',
                          labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 8),
                      TextField(
                        controller: _customEndpointController,
                        style: const TextStyle(fontSize: 13),
                        decoration: InputDecoration(
                          labelText: 'Custom API Endpoint (tùy chọn URL server riêng)',
                          hintText: 'https://your-server.com/api/verify_ig',
                          labelStyle: const TextStyle(fontSize: 12, color: Color(0xFF6B7280)),
                          contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),

                const SizedBox(height: 14),

                // 6. Action Button: "▷ Bắt đầu xác minh" (Vibrant Purple/Violet Gradient)
                Container(
                  width: double.infinity,
                  height: 48,
                  decoration: BoxDecoration(
                    gradient: const LinearGradient(
                      colors: [Color(0xFFD946EF), Color(0xFF8B5CF6), Color(0xFF7C3AED)],
                      begin: Alignment.centerLeft,
                      end: Alignment.centerRight,
                    ),
                    borderRadius: BorderRadius.circular(10),
                    boxShadow: [
                      BoxShadow(
                        color: const Color(0xFF8B5CF6).withValues(alpha: 0.35),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: _isLoading ? null : _startVerification,
                      child: Center(
                        child: _isLoading
                            ? Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  const SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 2.5,
                                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _progressMessage ?? 'Đang xử lý xác minh...',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              )
                            : const Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(Icons.play_arrow_rounded, color: Colors.white, size: 24),
                                  SizedBox(width: 6),
                                  Text(
                                    'Bắt đầu xác minh',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 15,
                                      fontWeight: FontWeight.bold,
                                      letterSpacing: 0.3,
                                    ),
                                  ),
                                ],
                              ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),

          // 7. Verification Result Card
          if (_verifyResult != null) ...[
            const SizedBox(height: 16),
            _buildResultCard(_verifyResult!),
          ],
        ],
      ),
    );

    if (widget.isTab) {
      return Scaffold(
        backgroundColor: const Color(0xFFF9FAFB),
        appBar: AppBar(
          title: const Text('Xác minh Instagram (Cookie)'),
          backgroundColor: Colors.white,
          elevation: 0,
          centerTitle: true,
          titleTextStyle: const TextStyle(
            fontSize: 17,
            fontWeight: FontWeight.bold,
            color: Color(0xFF1F2937),
          ),
        ),
        body: SafeArea(child: cardContent),
      );
    }

    return Scaffold(
      backgroundColor: const Color(0xFFF9FAFB),
      appBar: AppBar(
        title: const Text('Xác minh Instagram qua Cookie'),
        elevation: 0,
        backgroundColor: Colors.white,
        iconTheme: const IconThemeData(color: Color(0xFF1F2937)),
        titleTextStyle: const TextStyle(
          fontSize: 17,
          fontWeight: FontWeight.bold,
          color: Color(0xFF1F2937),
        ),
      ),
      body: SafeArea(child: cardContent),
    );
  }

  Widget _buildPhotoContainer({
    required Uint8List? bytes,
    required String label,
    double height = 180,
    required VoidCallback onPick,
    required VoidCallback onRemove,
  }) {
    if (bytes != null) {
      return Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF3F4F6),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFE5E7EB)),
        ),
        child: Stack(
          alignment: Alignment.center,
          children: [
            ClipRRect(
              borderRadius: BorderRadius.circular(9),
              child: Image.memory(
                bytes,
                fit: BoxFit.contain,
                height: height,
                width: double.infinity,
              ),
            ),
            Positioned(
              top: 6,
              right: 6,
              child: GestureDetector(
                onTap: onRemove,
                child: Container(
                  padding: const EdgeInsets.all(5),
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.9),
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.1),
                        blurRadius: 4,
                      ),
                    ],
                  ),
                  child: const Icon(
                    Icons.delete_outline_rounded,
                    color: Color(0xFFEF4444),
                    size: 18,
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    }

    return GestureDetector(
      onTap: onPick,
      child: Container(
        height: height,
        width: double.infinity,
        decoration: BoxDecoration(
          color: const Color(0xFFF9FAFB),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: const Color(0xFFD1D5DB), style: BorderStyle.solid),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(10),
              decoration: const BoxDecoration(
                color: Color(0xFFF3F4F6),
                shape: BoxShape.circle,
              ),
              child: const Icon(
                Icons.add_photo_alternate_outlined,
                color: Color(0xFF9CA3AF),
                size: 26,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              label,
              style: const TextStyle(
                fontSize: 13,
                fontWeight: FontWeight.w500,
                color: Color(0xFF6B7280),
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildResultCard(InstagramVerifyResult result) {
    Color statusColor;
    IconData statusIcon;

    switch (result.status) {
      case InstagramVerifyStatus.success:
      case InstagramVerifyStatus.inReview:
        statusColor = const Color(0xFF10B981);
        statusIcon = Icons.check_circle_rounded;
        break;
      case InstagramVerifyStatus.checkpointFound:
        statusColor = const Color(0xFFF59E0B);
        statusIcon = Icons.link_rounded;
        break;
      case InstagramVerifyStatus.sessionExpired:
        statusColor = const Color(0xFFEF4444);
        statusIcon = Icons.warning_amber_rounded;
        break;
      case InstagramVerifyStatus.error:
        statusColor = const Color(0xFFEF4444);
        statusIcon = Icons.error_outline_rounded;
        break;
    }

    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: statusColor.withValues(alpha: 0.3), width: 1.5),
        boxShadow: [
          BoxShadow(
            color: statusColor.withValues(alpha: 0.08),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      padding: const EdgeInsets.all(16.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(statusIcon, color: statusColor, size: 22),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  result.title,
                  style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                    color: statusColor,
                  ),
                ),
              ),
              if (result.userId != null)
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: const Color(0xFFF3F4F6),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: Text(
                    'UID: ${result.userId}',
                    style: const TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: Color(0xFF4B5563)),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 10),
          Text(
            result.message,
            style: const TextStyle(fontSize: 13, color: Color(0xFF374151), height: 1.4),
          ),
          if (result.checkpointUrl != null && result.checkpointUrl!.isNotEmpty) ...[
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: const Color(0xFFF9FAFB),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: const Color(0xFFE5E7EB)),
              ),
              child: Row(
                children: [
                  const Icon(Icons.link, size: 16, color: Colors.blue),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text(
                      result.checkpointUrl!,
                      style: const TextStyle(fontSize: 11, color: Colors.blue),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: ElevatedButton.icon(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.blue,
                      foregroundColor: Colors.white,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.open_in_browser, size: 16),
                    label: const Text('Mở trình duyệt', style: TextStyle(fontSize: 13)),
                    onPressed: () async {
                      final uri = Uri.parse(result.checkpointUrl!);
                      if (await canLaunchUrl(uri)) {
                        await launchUrl(uri, mode: LaunchMode.externalApplication);
                      }
                    },
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      foregroundColor: Colors.blue,
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                      padding: const EdgeInsets.symmetric(vertical: 10),
                    ),
                    icon: const Icon(Icons.copy_rounded, size: 16),
                    label: const Text('Sao chép link', style: TextStyle(fontSize: 13)),
                    onPressed: () {
                      Clipboard.setData(ClipboardData(text: result.checkpointUrl!));
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(content: Text('Đã sao chép link xác minh!')),
                      );
                    },
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
