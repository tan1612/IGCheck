import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
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

  /// Nén ảnh trước khi gửi để tối ưu tốc độ truyền qua mạng (từ 10MB xuống ~150KB)
  Future<List<int>> _compressImageIfNeeded(List<int> bytes) async {
    if (bytes.length < 500 * 1024) return bytes;
    try {
      final result = await FlutterImageCompress.compressWithList(
        Uint8List.fromList(bytes),
        minWidth: 1024,
        minHeight: 1024,
        quality: 80,
      );
      if (result.isNotEmpty && result.length < bytes.length) {
        debugPrint('⚡ AI Service: Đã nén ảnh từ ${(bytes.length / 1024 / 1024).toStringAsFixed(2)}MB xuống ${(result.length / 1024).toStringAsFixed(1)}KB!');
        return result;
      }
    } catch (e) {
      debugPrint('AI Service warning nén ảnh: $e');
    }
    return bytes;
  }

  /// Tự động hỏi Google Gemini API danh sách các Model ĐANG HOẠT ĐỘNG cho API Key này
  Future<List<String>> _fetchAvailableModels() async {
    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 4);
      dio.options.receiveTimeout = const Duration(seconds: 4);
      final url = 'https://generativelanguage.googleapis.com/v1beta/models?key=$_apiKey';
      final response = await dio.get(url);

      if (response.statusCode == 200 && response.data != null) {
        final modelsList = response.data['models'] as List?;
        if (modelsList != null) {
          final valid = <String>[];
          for (final m in modelsList) {
            final name = m['name']?.toString().replaceFirst('models/', '');
            final methods = m['supportedGenerationMethods'] as List?;
            if (name != null && methods != null && methods.contains('generateContent')) {
              // Bỏ qua các model chuyên embedding
              if (!name.contains('embedding') && !name.contains('imagen') && !name.contains('aqa')) {
                valid.add(name);
              }
            }
          }
          if (valid.isNotEmpty) {
            // Sắp xếp ưu tiên các model 'flash' lên đầu tiên để đạt tốc độ đọc cực nhanh
            valid.sort((a, b) {
              final aFlash = a.contains('flash');
              final bFlash = b.contains('flash');
              if (aFlash && !bFlash) return -1;
              if (!aFlash && bFlash) return 1;
              return a.compareTo(b);
            });
            debugPrint('🎯 AI Service: Đã tự động phát hiện danh sách Model khả dụng cho Key: $valid');
            return valid;
          }
        }
      }
    } catch (e) {
      debugPrint('AI Service: Không thể lấy danh sách Model động: $e');
    }

    // Danh sách dự phòng chuẩn xác nếu không thể tải danh sách động
    return [
      'gemini-1.5-flash-002',
      'gemini-1.5-flash-001',
      'gemini-1.5-flash-latest',
      'gemini-1.5-pro-002',
      'gemini-1.5-pro-latest',
      'gemini-2.0-flash-lite-preview-02-05',
    ];
  }

  /// Gửi ảnh lên Gemini Vision để trích xuất tên
  Future<String?> extractNameFromImage(XFile imageFile) async {
    if (_apiKey.isEmpty || _apiKey == 'NHET_KEY_CUA_NI_VAO_DAY') {
      debugPrint('AI Service: Chưa cấu hình Gemini API Key.');
      return null;
    }

    try {
      final rawBytes = await imageFile.readAsBytes();
      final compressedBytes = await _compressImageIfNeeded(rawBytes);
      return await _callGeminiRestApi(compressedBytes);
    } catch (e) {
      debugPrint('Lỗi đọc file ảnh: $e');
      return 'LỖI: Không thể đọc file ảnh!';
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
      dio.options.connectTimeout = const Duration(seconds: 8);
      dio.options.receiveTimeout = const Duration(seconds: 10);
      final responseHttp = await dio.get(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final rawBytes = responseHttp.data as List<int>;
      final compressedBytes = await _compressImageIfNeeded(rawBytes);
      return await _callGeminiRestApi(compressedBytes);
    } catch (e) {
      debugPrint('Lỗi tải ảnh từ URL: $e');
      return 'LỖI: Không thể tải ảnh từ URL!';
    }
  }

  /// Gọi trực tiếp Google Gemini REST API với danh sách Model hoạt động động
  Future<String?> _callGeminiRestApi(List<int> bytes) async {
    final base64Image = base64Encode(bytes);

    const promptText = '''
Đây là ảnh giấy tờ tùy thân. Hãy trích xuất và chỉ trả về DUY NHẤT Họ và Tên (Full Name) của người trên giấy tờ. 
Không giải thích thêm, không có dấu ngoặc kép, không dùng markdown. 
Nếu hình ảnh bị mờ hoặc không tìm thấy tên hợp lệ, hãy trả về chữ 'KHÔNG ĐỌC ĐƯỢC'.
''';

    // Tự động tìm các model đang hoạt động trên Google AI Studio
    final activeModels = await _fetchAvailableModels();

    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 6);
    dio.options.receiveTimeout = const Duration(seconds: 15);

    final errors = <String>[];

    for (final model in activeModels) {
      try {
        final url = 'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_apiKey';
        debugPrint('AI Service REST: Đang gọi model $model...');

        final response = await dio.post(
          url,
          options: Options(
            headers: {'Content-Type': 'application/json'},
            receiveTimeout: const Duration(seconds: 8),
          ),
          data: {
            "contents": [
              {
                "parts": [
                  {"text": promptText},
                  {
                    "inline_data": {
                      "mime_type": "image/jpeg",
                      "data": base64Image
                    }
                  }
                ]
              }
            ]
          },
        );

        if (response.statusCode == 200 && response.data != null) {
          final data = response.data;
          final candidates = data['candidates'] as List?;
          if (candidates != null && candidates.isNotEmpty) {
            final content = candidates[0]['content'];
            if (content != null) {
              final parts = content['parts'] as List?;
              if (parts != null && parts.isNotEmpty) {
                final resultText = parts[0]['text']?.toString().trim();
                if (resultText != null && resultText.isNotEmpty) {
                  debugPrint('🎉 AI Service REST: Thành công rực rỡ với model $model -> $resultText');
                  return resultText;
                }
              }
            }
          }
        }
      } catch (e) {
        String errMsg = '';
        if (e is DioException) {
          final resp = e.response;
          if (resp != null && resp.data != null) {
            final errorData = resp.data;
            if (errorData is Map && errorData['error'] != null) {
              errMsg = errorData['error']['message']?.toString() ?? e.message ?? e.toString();
            } else {
              errMsg = e.message ?? e.toString();
            }
          } else {
            errMsg = e.message ?? e.toString();
          }
        } else {
          errMsg = e.toString();
        }
        debugPrint('AI Service REST: Model $model chưa kích hoạt/bị bỏ qua: $errMsg');
        errors.add(errMsg);
      }
    }

    if (errors.isNotEmpty) {
      final first = errors.first;
      if (first.contains('API key not valid') || first.contains('API_KEY_INVALID') || first.contains('invalid API key')) {
        return 'LỖI: Gemini API Key không hợp lệ. Vui lòng kiểm tra lại API Key!';
      }
      if (first.contains('429') || first.contains('quota') || first.contains('RESOURCE_EXHAUSTED')) {
        return 'LỖI: Quá tải hạn ngạch API (Quota Limit), vui lòng thử lại sau 1 phút!';
      }
      return 'LỖI: ${errors.first}';
    }

    return 'KHÔNG ĐỌC ĐƯỢC';
  }
}
