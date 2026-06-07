import 'dart:io';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';

class AIService {
  // Lấy API Key từ biến môi trường (Environment Variable) lúc build app
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal();

  /// Gửi ảnh lên Gemini Vision để trích xuất tên
  Future<String?> extractNameFromImage(XFile imageFile) async {
    // Nếu chưa cấu hình API key, trả về null để sử dụng logic mock hoặc báo lỗi
    if (_apiKey.isEmpty) {
      debugPrint('AI Service: Chưa cấu hình Gemini API Key. Đang trả về mock data...');
      return null;
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _apiKey,
        requestOptions: const RequestOptions(apiVersion: 'v1beta'),
      );

      final imageBytes = await imageFile.readAsBytes();
      
      final prompt = TextPart(
        '''
Đây là ảnh giấy tờ tùy thân. Hãy trích xuất và chỉ trả về DUY NHẤT Họ và Tên (Full Name) của người trên giấy tờ. 
Không giải thích thêm, không có dấu ngoặc kép, không dùng markdown. 
Nếu hình ảnh bị mờ hoặc không tìm thấy tên hợp lệ, hãy trả về chữ 'KHÔNG ĐỌC ĐƯỢC'.
'''
      );
      
      final imagePart = DataPart('image/jpeg', imageBytes);

      final response = await model.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      if (response.text != null && response.text!.trim().isNotEmpty) {
        return response.text!.trim();
      }
      return 'KHÔNG ĐỌC ĐƯỢC';
    } catch (e) {
      debugPrint('Lỗi khi gọi Gemini API: $e');
      if (e.toString().contains('429') || e.toString().contains('quota') || e.toString().contains('Too Many Requests')) {
        return 'LỖI: Quá tải máy chủ AI, vui lòng thử lại sau 1 phút!';
      }
      return 'LỖI QUÉT ẢNH';
    }
  }

  /// Gửi ảnh từ URL lên Gemini Vision để trích xuất tên
  Future<String?> extractNameFromImageUrl(String imageUrl) async {
    if (_apiKey.isEmpty) {
      debugPrint('AI Service: Chưa cấu hình Gemini API Key. Đang trả về mock data...');
      return null;
    }

    try {
      final model = GenerativeModel(
        model: 'gemini-1.5-flash',
        apiKey: _apiKey,
        requestOptions: const RequestOptions(apiVersion: 'v1beta'),
      );

      // Tải ảnh từ URL thành bytes
      final dio = Dio();
      final responseHttp = await dio.get(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = responseHttp.data;
      
      final prompt = TextPart(
        '''
Đây là ảnh giấy tờ tùy thân. Hãy trích xuất và chỉ trả về DUY NHẤT Họ và Tên (Full Name) của người trên giấy tờ. 
Không giải thích thêm, không có dấu ngoặc kép, không dùng markdown. 
Nếu hình ảnh bị mờ hoặc không tìm thấy tên hợp lệ, hãy trả về chữ 'KHÔNG ĐỌC ĐƯỢC'.
'''
      );
      
      final imagePart = DataPart('image/jpeg', bytes);

      final response = await model.generateContent([
        Content.multi([prompt, imagePart])
      ]);

      if (response.text != null && response.text!.trim().isNotEmpty) {
        return response.text!.trim();
      }
      return 'KHÔNG ĐỌC ĐƯỢC';
    } catch (e) {
      debugPrint('Lỗi khi gọi Gemini API từ URL: $e');
      if (e.toString().contains('429') || e.toString().contains('quota') || e.toString().contains('Too Many Requests')) {
        return 'LỖI: Quá tải máy chủ AI, vui lòng thử lại sau 1 phút!';
      }
      return 'LỖI QUÉT ẢNH';
    }
  }
}
