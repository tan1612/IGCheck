import 'dart:io';
import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

class NotificationService extends ChangeNotifier {
  // --- TELEGRAM BOT CONFIG ---
  // Thay thế bằng Token của Telegram Bot bạn tạo từ @BotFather
  static const String _telegramBotToken = '8655291561:AAHksFJvgl0hkEnVRhD2JVDu6bJ54wmaZPY';
  // ---------------------------

  final FlutterLocalNotificationsPlugin _localNotificationsPlugin = FlutterLocalNotificationsPlugin();
  
  String? _fcmToken;
  bool _hasPermission = false;
  Function(String requestId)? _onNotificationTap;

  String? get fcmToken => _fcmToken;
  bool get hasPermission => _hasPermission;

  NotificationService() {
    _initLocalNotifications();
  }

  Future<void> _initLocalNotifications() async {
    const androidInitSettings = AndroidInitializationSettings('@mipmap/ic_launcher');
    const iosInitSettings = DarwinInitializationSettings(
      requestAlertPermission: false,
      requestBadgePermission: false,
      requestSoundPermission: false,
    );

    const initSettings = InitializationSettings(
      android: androidInitSettings,
      iOS: iosInitSettings,
    );

    await _localNotificationsPlugin.initialize(
      settings: initSettings,
      onDidReceiveNotificationResponse: (NotificationResponse response) {
        if (response.payload != null && _onNotificationTap != null) {
          _onNotificationTap!(response.payload!);
        }
      },
    );
  }

  void setOnNotificationTap(Function(String) callback) {
    _onNotificationTap = callback;
  }

  Future<bool> requestNotificationPermission() async {
    if (kIsWeb) {
      _hasPermission = true;
    } else if (Platform.isIOS) {
      final result = await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<IOSFlutterLocalNotificationsPlugin>()
          ?.requestPermissions(
            alert: true,
            badge: true,
            sound: true,
          );
      _hasPermission = result ?? false;
    } else if (Platform.isAndroid) {
      final result = await _localNotificationsPlugin
          .resolvePlatformSpecificImplementation<AndroidFlutterLocalNotificationsPlugin>()
          ?.requestNotificationsPermission();
      _hasPermission = result ?? false;
    }

    // Since we rely on Telegram instead of FCM for Sideloadly iOS apps, 
    // we generate a dummy FCM token if one doesn't exist.
    _fcmToken = 'dummy_fcm_token_sideloadly_${DateTime.now().millisecondsSinceEpoch}';
    notifyListeners();
    return _hasPermission;
  }

  /// Hiển thị Local Notification (foreground)
  Future<void> showLocalNotification(String title, String body, String payload) async {
    const androidDetails = AndroidNotificationDetails(
      'igcheck_main_channel',
      'IGCheck Notifications',
      importance: Importance.max,
      priority: Priority.high,
    );
    const iosDetails = DarwinNotificationDetails(
      presentAlert: true,
      presentBadge: true,
      presentSound: true,
    );
    const details = NotificationDetails(android: androidDetails, iOS: iosDetails);

    await _localNotificationsPlugin.show(
      id: DateTime.now().millisecondsSinceEpoch.remainder(100000),
      title: title,
      body: body,
      notificationDetails: details,
      payload: payload,
    );
  }

  /// Gửi thông báo Telegram
  Future<void> sendTelegramMessage(String message, {String? targetChatId}) async {
    if (_telegramBotToken == 'YOUR_TELEGRAM_BOT_TOKEN_HERE' || _telegramBotToken.isEmpty) {
      debugPrint('Telegram Bot Token chưa được cấu hình. Bỏ qua gửi thông báo.');
      return;
    }

    if (targetChatId == null || targetChatId.isEmpty) {
      debugPrint('Chưa có Chat ID của người nhận. Bỏ qua gửi thông báo.');
      return;
    }

    try {
      final dio = Dio();
      final response = await dio.post(
        'https://api.telegram.org/bot$_telegramBotToken/sendMessage',
        data: {
          'chat_id': targetChatId,
          'text': message,
          'parse_mode': 'HTML',
        },
      );
      
      if (response.statusCode == 200) {
        debugPrint('Đã gửi thông báo Telegram thành công.');
      } else {
        debugPrint('Lỗi gửi Telegram: ${response.statusCode}');
      }
    } catch (e) {
      debugPrint('Lỗi khi gọi Telegram API: $e');
    }
  }

  // Simulate receiving a notification in foreground (for testing or real usage)
  void simulateIncomingNotification(BuildContext context, String title, String body, String requestId) {
    if (_hasPermission) {
      // Trigger actual local push notification
      showLocalNotification(title, body, requestId);
    }
    
    // Also show snackbar inside the app as a banner
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        margin: const EdgeInsets.all(16),
        backgroundColor: const Color(0xFF8E8EF8),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        duration: const Duration(seconds: 4),
        content: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                const Icon(Icons.notifications_active, color: Colors.white, size: 18),
                const SizedBox(width: 8),
                Text(
                  title,
                  style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.white),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Text(body, style: const TextStyle(color: Colors.white)),
          ],
        ),
        action: SnackBarAction(
          label: 'Xem',
          textColor: Colors.white,
          onPressed: () {
            if (_onNotificationTap != null) {
              _onNotificationTap!(requestId);
            }
          },
        ),
      ),
    );
  }
}
