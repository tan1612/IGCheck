import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:url_launcher/url_launcher.dart';
import '../services/ai_service.dart';
import '../services/auth_service.dart';

/// Hiển thị hộp thoại cấu hình Google Gemini API Key trực tiếp.
/// Cho phép dán nhanh từ clipboard, mở link lấy key miễn phí, và lưu ngay vào tài khoản.
Future<void> showGeminiApiKeyDialog(
  BuildContext context, {
  VoidCallback? onKeySaved,
}) async {
  final authService = Provider.of<AuthService>(context, listen: false);
  final user = authService.currentUser;
  final currentKey = (user?.geminiApiKey?.isNotEmpty == true)
      ? user!.geminiApiKey!
      : AIService().currentApiKey;

  final keyController = TextEditingController(text: currentKey);
  bool obscure = true;

  await showDialog<void>(
    context: context,
    builder: (ctx) {
      return StatefulBuilder(
        builder: (context, setDialogState) {
          final isConfigured = AIService().isConfigured;
          final masked = AIService().maskedApiKey;

          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 8),
            actionsPadding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: Colors.purple.withValues(alpha: 0.12),
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(Icons.auto_awesome, color: Colors.purple, size: 24),
                ),
                const SizedBox(width: 12),
                const Expanded(
                  child: Text(
                    'Cấu hình Gemini API Key',
                    style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Dùng để nhận diện và tự động đọc họ tên từ ảnh giấy tờ (CCCD, Giấy phép lái xe, Hộ chiếu). Key sẽ được lưu bảo mật trong tài khoản của bạn.',
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700, height: 1.3),
                  ),
                  const SizedBox(height: 12),
                  // Trạng thái hiện tại
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: isConfigured ? Colors.green.shade50 : Colors.amber.shade50,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(
                        color: isConfigured ? Colors.green.shade200 : Colors.amber.shade200,
                      ),
                    ),
                    child: Row(
                      children: [
                        Icon(
                          isConfigured ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                          size: 18,
                          color: isConfigured ? Colors.green.shade700 : Colors.amber.shade800,
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            isConfigured
                                ? 'Đang hoạt động: $masked'
                                : 'Chưa cấu hình API Key',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.w600,
                              color: isConfigured ? Colors.green.shade900 : Colors.amber.shade900,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 16),
                  TextField(
                    controller: keyController,
                    obscureText: obscure,
                    style: const TextStyle(fontSize: 14, fontFamily: 'monospace'),
                    decoration: InputDecoration(
                      labelText: 'Gemini API Key',
                      hintText: 'Dán mã API Key bắt đầu bằng AIza...',
                      prefixIcon: const Icon(Icons.vpn_key_outlined, size: 20),
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(10)),
                      suffixIcon: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: Icon(
                              obscure ? Icons.visibility_off : Icons.visibility,
                              size: 18,
                              color: Colors.grey.shade600,
                            ),
                            tooltip: obscure ? 'Hiện mã' : 'Ẩn mã',
                            onPressed: () => setDialogState(() => obscure = !obscure),
                          ),
                          IconButton(
                            icon: const Icon(Icons.content_paste_rounded, size: 18, color: Colors.purple),
                            tooltip: 'Dán từ bộ nhớ tạm',
                            onPressed: () async {
                              final data = await Clipboard.getData(Clipboard.kTextPlain);
                              final text = data?.text?.trim() ?? '';
                              if (text.isNotEmpty) {
                                keyController.text = text;
                                setDialogState(() {});
                              }
                            },
                          ),
                          if (keyController.text.isNotEmpty)
                            IconButton(
                              icon: const Icon(Icons.clear, size: 18, color: Colors.grey),
                              tooltip: 'Xóa',
                              onPressed: () {
                                keyController.clear();
                                setDialogState(() {});
                              },
                            ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(height: 14),
                  // Hướng dẫn lấy key miễn phí
                  Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: Colors.grey.shade300),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Row(
                          children: [
                            Icon(Icons.lightbulb_outline, size: 16, color: Colors.amber),
                            SizedBox(width: 6),
                            Text(
                              'Cách lấy API Key miễn phí (10 giây):',
                              style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                          ],
                        ),
                        const SizedBox(height: 6),
                        const Text(
                          '1. Truy cập Google AI Studio (đăng nhập tài khoản Google).\n2. Bấm "Create API key" -> Sao chép mã và dán vào ô bên trên.',
                          style: TextStyle(fontSize: 11.5, color: Color(0xFF444444), height: 1.3),
                        ),
                        const SizedBox(height: 8),
                        InkWell(
                          borderRadius: BorderRadius.circular(6),
                          onTap: () async {
                            const url = 'https://aistudio.google.com/app/apikey';
                            await Clipboard.setData(const ClipboardData(text: url));
                            try {
                              final uri = Uri.parse(url);
                              if (await canLaunchUrl(uri)) {
                                await launchUrl(uri, mode: LaunchMode.externalApplication);
                              }
                            } catch (_) {}
                            if (context.mounted) {
                              ScaffoldMessenger.of(context).showSnackBar(
                                const SnackBar(
                                  content: Text('Đã sao chép liên kết Google AI Studio: https://aistudio.google.com/app/apikey'),
                                  backgroundColor: Colors.purple,
                                  duration: Duration(seconds: 3),
                                ),
                              );
                            }
                          },
                          child: const Padding(
                            padding: EdgeInsets.symmetric(vertical: 4),
                            child: Row(
                              children: [
                                Icon(Icons.open_in_new, size: 14, color: Colors.purple),
                                SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'Mở aistudio.google.com/app/apikey',
                                    style: TextStyle(
                                      fontSize: 12,
                                      color: Colors.purple,
                                      fontWeight: FontWeight.bold,
                                      decoration: TextDecoration.underline,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.check, size: 18),
                label: const Text('Lưu & Quét ngay'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.purple,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                ),
                onPressed: () async {
                  final key = keyController.text.trim();
                  if (key.isEmpty) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(content: Text('Vui lòng nhập hoặc dán Gemini API Key!')),
                    );
                    return;
                  }
                  Navigator.pop(ctx);
                  authService.updateGeminiApiKey(key);
                  AIService().setApiKeyForSession(key);

                  if (context.mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text('Đã cập nhật Gemini API Key! Đang tiến hành quét...'),
                        backgroundColor: Colors.teal,
                      ),
                    );
                  }
                  onKeySaved?.call();
                },
              ),
            ],
          );
        },
      );
    },
  );
  keyController.dispose();
}
