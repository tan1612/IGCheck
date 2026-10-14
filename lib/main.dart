import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';
import 'app.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  FlutterError.onError = (FlutterErrorDetails details) {
    try {
      File('app_dart_error.log').writeAsStringSync(
        'FLUTTER ERROR: ${details.exceptionAsString()}\n${details.stack}\n',
        mode: FileMode.append,
      );
    } catch (_) {}
    FlutterError.presentError(details);
  };

  PlatformDispatcher.instance.onError = (error, stack) {
    try {
      File('app_dart_error.log').writeAsStringSync(
        'PLATFORM ERROR: $error\n$stack\n',
        mode: FileMode.append,
      );
    } catch (_) {}
    return true; // prevent crash
  };
  
  // Khởi động giao diện ngay lập tức để cửa sổ ứng dụng xuất hiện tức thì
  runApp(const IGCheckApp());

  try {
    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    ).timeout(const Duration(seconds: 3));
  } catch (e) {
    debugPrint('Firebase init error (bỏ qua nếu chưa cấu hình): $e');
  }
}
