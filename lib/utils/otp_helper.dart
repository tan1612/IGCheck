import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

class OtpHelper {
  /// Fetches a 6-digit Time-based One-Time Password (TOTP) from 2fa.live API
  static Future<String> fetchOtp(String secret) async {
    final cleanSecret = secret.replaceAll(' ', '').trim();
    if (cleanSecret.isEmpty) {
      throw Exception('Khóa bảo mật 2FA trống');
    }

    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 10);
    dio.options.receiveTimeout = const Duration(seconds: 10);

    final response = await dio.get('https://2fa.live/tok/$cleanSecret');
    
    final data = response.data;
    String? token;

    if (data is Map) {
      token = data['token']?.toString();
    } else if (data is String) {
      final decoded = json.decode(data);
      if (decoded is Map) {
        token = decoded['token']?.toString();
      }
    }

    if (token == null || token.trim().isEmpty) {
      throw Exception('Không tìm thấy mã OTP trong phản hồi từ server.');
    }

    return token.trim();
  }

  /// Helper to fetch and show the OTP in a beautiful dialog, auto-copying it to clipboard
  static Future<void> showOtpDialog(BuildContext context, String secret) async {
    final cleanSecret = secret.replaceAll(' ', '').trim();
    if (cleanSecret.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Vui lòng điền khóa bảo mật 2FA trước.')),
      );
      return;
    }

    // 1. Show loading dialog
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => const AlertDialog(
        content: Row(
          children: [
            CircularProgressIndicator(color: Colors.blue),
            SizedBox(width: 20),
            Expanded(child: Text('Đang lấy mã OTP 2FA...')),
          ],
        ),
      ),
    );

    try {
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
                Text('Lỗi lấy mã 2FA'),
              ],
            ),
            content: Text(
              'Không thể lấy mã OTP từ 2fa.live.\nChi tiết: ${e.toString().replaceAll('Exception: ', '')}\n\nVui lòng kiểm tra lại khóa 2FA hoặc kết nối mạng.',
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
