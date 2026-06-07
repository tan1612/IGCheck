import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:flutter/foundation.dart';

class AIService {
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  /// Gửi ảnh lên Gemini Vision để trích xuất tên
  Future<String?> extractNameFromImage(XFile imageFile) async {
    // Trả về null để UI tự động chạy dữ liệu giả lập (MOCK) cho dễ test
    return null;
  }

  /// Gửi ảnh từ URL lên Gemini Vision để trích xuất tên
  Future<String?> extractNameFromImageUrl(String imageUrl) async {
    // Trả về null để UI tự động chạy dữ liệu giả lập (MOCK) cho dễ test
    return null;
  }
}


