import 'package:otp/otp.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpHelper {
  /// Generates a 6-digit Time-based One-Time Password (TOTP) locally
  static Future<String> fetchOtp(String secret) async {
    // Standardize the secret key (remove spaces, make uppercase as standard Base32)
    final cleanSecret = secret.replaceAll(' ', '').toUpperCase().trim();
    if (cleanSecret.isEmpty) {
      throw Exception('Khóa bảo mật 2FA trống');
    }

    try {
      // Generate TOTP code locally using RFC 6238 implementation
      final code = OTP.generateTOTPCodeString(
        cleanSecret,
        DateTime.now().millisecondsSinceEpoch,
        length: 6,
        interval: 30,
        algorithm: Algorithm.SHA1,
        isGoogle: true, // Crucial: standard 2FA secrets are Base32 encoded (Google Authenticator style)
      );
      return code;
    } catch (e) {
      throw Exception('Không thể giải mã khóa 2FA. Vui lòng kiểm tra lại định dạng khóa.');
    }
  }

  /// Helper to generate and show the OTP in a beautiful dialog, auto-copying it to clipboard
  static Future<void> showOtpDialog(BuildContext context, String secret) async {
    final cleanSecret = secret.replaceAll(' ', '').trim();
    if (cleanSecret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng điền khóa bảo mật 2FA trước.')),
      );
      return;
    }

    // 1. Show loading dialog (shows briefly for UX transition)
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(width: 20),
            Expanded(child: Text('Đang tạo mã OTP 2FA...')),
          ],
        ),
      ),
    );

    try {
      // Brief delay to make the transition feel natural and show loading for a split second
      await Future.delayed(const Duration(milliseconds: 250));
      final otp = await fetchOtp(cleanSecret);
      
      // Close loading dialog
      if (context.mounted) {
        Navigator.pop(context);
      }

      // Auto copy to clipboard
      await Clipboard.setData(ClipboardData(text: otp));

      // 2. Show OTP Success Dialog
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(
              children: [
                Icon(Icons.security, color: Colors.green),
                SizedBox(width: 8),
                Text('Mã OTP 2FA', style: TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Mã xác thực đã được tự động sao chép vào bộ nhớ tạm!',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 13, color: Colors.grey),
                ),
                const SizedBox(height: 20),
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                  decoration: BoxDecoration(
                    color: Colors.green.shade50,
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.green.shade200),
                  ),
                  child: Text(
                    otp,
                    style: const TextStyle(
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 4,
                      color: Colors.green,
                      fontFamily: 'Courier',
                    ),
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Mã này thay đổi sau mỗi 30 giây.',
                  style: TextStyle(fontSize: 11, fontStyle: FontStyle.italic, color: Colors.grey),
                ),
              ],
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
              ElevatedButton.icon(
                icon: const Icon(Icons.copy, size: 16),
                label: const Text('Sao chép lại'),
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.blue,
                  foregroundColor: Colors.white,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
                ),
                onPressed: () {
                  Clipboard.setData(ClipboardData(text: otp));
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(content: Text('Đã sao chép mã OTP!'), duration: Duration(seconds: 1)),
                  );
                },
              ),
            ],
          ),
        );
      }
    } catch (e) {
      // Close loading dialog
      if (context.mounted) {
        Navigator.pop(context);
      }

      // Show error dialog
      if (context.mounted) {
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Row(
              children: [
                Icon(Icons.error_outline, color: Colors.red),
                SizedBox(width: 8),
                Text('Lỗi giải mã 2FA'),
              ],
            ),
            content: Text(
              'Không thể lấy mã OTP.\nChi tiết: ${e.toString().replaceAll('Exception: ', '')}\n\nVui lòng kiểm tra lại định dạng khóa 2FA.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx),
                child: const Text('Đóng'),
              ),
            ],
          ),
        );
      }
    }
  }
}
