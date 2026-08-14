import 'package:dio/dio.dart' hide RequestOptions;
import 'package:image_picker/image_picker.dart';
import 'package:google_generative_ai/google_generative_ai.dart';
import 'package:flutter/foundation.dart';

class AIService {
  // Đọc API Key bảo mật từ Environment Variables
  static const String _apiKey = String.fromEnvironment('GEMINI_API_KEY', defaultValue: '');
  
  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal() {
    if (_apiKey.isEmpty || _apiKey == 'NHET_KEY_CUA_NI_VAO_DAY') {
      debugPrint('⚠️ AI Service: Chưa cấu hình GEMINI_API_KEY!');
    } else {
      final masked = _apiKey.length > 8
          ? '${_apiKey.substring(0, 4)}...${_apiKey.substring(_apiKey.length - 4)}'
          : '***';
      debugPrint('🚀 AI Service: Đã tải thành công API Key từ Environment: $masked');
    }
  }

  /// Gửi ảnh lên Gemini Vision để trích xuất tên
  Future<String?> extractNameFromImage(XFile imageFile) async {
    if (_apiKey.isEmpty || _apiKey == 'NHET_KEY_CUA_NI_VAO_DAY') {
      debugPrint('AI Service: Chưa cấu hình Gemini API Key.');
      return null;
    }

    try {
      final imageBytes = await imageFile.readAsBytes();
      
      final prompt = TextPart(
        '''
Đây là ảnh giấy tờ tùy thân. Hãy trích xuất và chỉ trả về DUY NHẤT Họ và Tên (Full Name) của người trên giấy tờ. 
Không giải thích thêm, không có dấu ngoặc kép, không dùng markdown. 
Nếu hình ảnh bị mờ hoặc không tìm thấy tên hợp lệ, hãy trả về chữ 'KHÔNG ĐỌC ĐƯỢC'.
'''
      );
      
      final imagePart = DataPart('image/jpeg', imageBytes);

      // Danh sách các model chính thức của Google Gemini Vision (Ưu tiên gemini-1.5-flash cực nhanh)
      final modelCandidates = [
        'gemini-1.5-flash',
        'gemini-2.0-flash-exp',
        'gemini-1.5-pro',
      ];

      final errors = <Object>[];

      for (final modelName in modelCandidates) {
        try {
          debugPrint('AI Service: Đang gọi model $modelName...');
          final model = GenerativeModel(
            model: modelName,
            apiKey: _apiKey,
          );

          // Thêm timeout 8s để đảm bảo phản hồi tức thì
          final response = await model.generateContent([
            Content.multi([prompt, imagePart])
          ]).timeout(const Duration(seconds: 8));

          if (response.text != null && response.text!.trim().isNotEmpty) {
            final resultText = response.text!.trim();
            debugPrint('AI Service: Thành công với model $modelName -> $resultText');
            return resultText;
          }
        } catch (e) {
          debugPrint('Lỗi/Timeout với model $modelName: $e');
          errors.add(e);
        }
      }

      final hasQuotaError = errors.any((e) {
        final str = e.toString();
        return str.contains('429') || str.contains('quota') || str.contains('Too Many Requests');
      });

      if (hasQuotaError) {
        return 'LỖI: Quá tải máy chủ AI, vui lòng thử lại sau 1 phút!';
      }

      if (errors.isNotEmpty) {
        final firstErr = errors.first.toString();
        if (firstErr.contains('TimeoutException')) {
          return 'LỖI: Kết nối AI hết thời gian chờ, vui lòng thử lại!';
        }
        return 'LỖI: ${errors.first}';
      }
      return 'KHÔNG ĐỌC ĐƯỢC';
    } catch (e) {
      debugPrint('Lỗi tổng khi gọi Gemini API: $e');
      if (e.toString().contains('429') || e.toString().contains('quota') || e.toString().contains('Too Many Requests')) {
        return 'LỖI: Quá tải máy chủ AI, vui lòng thử lại sau 1 phút!';
      }
      return 'LỖI: $e';
    }
  }

  /// Gửi ảnh từ URL lên Gemini Vision để trích xuất tên
  Future<String?> extractNameFromImageUrl(String imageUrl) async {
    if (_apiKey.isEmpty || _apiKey == 'NHET_KEY_CUA_NI_VAO_DAY') {
      debugPrint('AI Service: Chưa cấu hình Gemini API Key.');
      return null;
    }

    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 10);
      final responseHttp = await dio.get(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final bytes = responseHttp.data;
      
      final prompt = TextPart(
        '''
Đây là ảnh giấy tờ tùy thân. Hãy trích xuất và chỉ trả về DUY NHẤT Họ và Tên (Full Name) của người trên giấy tờ. 
Không giải thích thêm, không có dấu ngoặc kép, không dùng markdown. 
If the image is blurry or has no valid name, return 'KHÔNG ĐỌC ĐƯỢC'.
'''
      );
      
      final imagePart = DataPart('image/jpeg', bytes);

      final modelCandidates = [
        'gemini-1.5-flash',
        'gemini-2.0-flash-exp',
        'gemini-1.5-pro',
      ];

      final errors = <Object>[];

      for (final modelName in modelCandidates) {
        try {
          debugPrint('AI Service: Đang gọi model $modelName từ URL...');
          final model = GenerativeModel(
            model: modelName,
            apiKey: _apiKey,
          );
          final response = await model.generateContent([
            Content.multi([prompt, imagePart])
          ]).timeout(const Duration(seconds: 8));

          if (response.text != null && response.text!.trim().isNotEmpty) {
            final resultText = response.text!.trim();
            debugPrint('AI Service: Thành công với model $modelName từ URL -> $resultText');
            return resultText;
          }
        } catch (e) {
          debugPrint('Lỗi/Timeout với model $modelName từ URL: $e');
          errors.add(e);
        }
      }

      final hasQuotaError = errors.any((e) {
        final str = e.toString();
        return str.contains('429') || str.contains('quota') || str.contains('Too Many Requests');
      });

      if (hasQuotaError) {
        return 'LỖI: Quá tải máy chủ AI, vui lòng thử lại sau 1 phút!';
      }

      if (errors.isNotEmpty) {
        return 'LỖI: ${errors.first}';
      }
      return 'KHÔNG ĐỌC ĐƯỢC';
    } catch (e) {
      debugPrint('Lỗi khi gọi Gemini API từ URL: $e');
      if (e.toString().contains('429') || e.toString().contains('quota') || e.toString().contains('Too Many Requests')) {
        return 'LỖI: Quá tải máy chủ AI, vui lòng thử lại sau 1 phút!';
      }
      return 'LỖI: $e';
    }
  }
}
