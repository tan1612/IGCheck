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

  /// Nén và resize ảnh trước khi gửi (giới hạn cạnh dài nhất <= 1568px, quality: 85)
  Future<List<int>> _compressAndResizeImage(List<int> bytes) async {
    final compressStopwatch = Stopwatch()..start();
    try {
      final result = await FlutterImageCompress.compressWithList(
        Uint8List.fromList(bytes),
        minWidth: 1568,
        minHeight: 1568,
        quality: 85,
        format: CompressFormat.jpeg,
      );
      compressStopwatch.stop();
      if (result.isNotEmpty && result.length < bytes.length) {
        debugPrint('⚡ [BENCHMARK] Nén & Resize ảnh xong trong ${compressStopwatch.elapsedMilliseconds} ms (Từ ${(bytes.length / 1024 / 1024).toStringAsFixed(2)}MB -> ${(result.length / 1024).toStringAsFixed(1)}KB)');
        return result;
      }
    } catch (e) {
      debugPrint('AI Service warning nén ảnh: $e');
    }
    compressStopwatch.stop();
    return bytes;
  }

  /// Gửi ảnh lên Gemini Vision để trích xuất tên
  Future<String?> extractNameFromImage(XFile imageFile) async {
    if (_apiKey.isEmpty || _apiKey == 'NHET_KEY_CUA_NI_VAO_DAY') {
      debugPrint('AI Service: Chưa cấu hình Gemini API Key.');
      return null;
    }

    final totalStopwatch = Stopwatch()..start();
    try {
      final rawBytes = await imageFile.readAsBytes();
      final compressedBytes = await _compressAndResizeImage(rawBytes);
      
      final result = await _callGeminiRestApi(compressedBytes);
      totalStopwatch.stop();
      debugPrint('⏱️ [BENCHMARK TOTAL] extractNameFromImage kết thúc trong: ${totalStopwatch.elapsedMilliseconds} ms (${(totalStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s)');
      return result;
    } catch (e) {
      totalStopwatch.stop();
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

    final totalStopwatch = Stopwatch()..start();
    try {
      final dio = Dio();
      dio.options.connectTimeout = const Duration(seconds: 8);
      dio.options.receiveTimeout = const Duration(seconds: 10);
      final responseHttp = await dio.get(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final rawBytes = responseHttp.data as List<int>;
      final compressedBytes = await _compressAndResizeImage(rawBytes);
      final result = await _callGeminiRestApi(compressedBytes);
      totalStopwatch.stop();
      debugPrint('⏱️ [BENCHMARK TOTAL] extractNameFromImageUrl kết thúc trong: ${totalStopwatch.elapsedMilliseconds} ms');
      return result;
    } catch (e) {
      totalStopwatch.stop();
      debugPrint('Lỗi tải ảnh từ URL: $e');
      return 'LỖI: Không thể tải ảnh từ URL!';
    }
  }

  /// Gọi trực tiếp Google Gemini REST API với các Model Flash tối ưu nhất
  Future<String?> _callGeminiRestApi(List<int> bytes) async {
    final apiStopwatch = Stopwatch()..start();
    final base64Image = base64Encode(bytes);

    const promptText = '''
Đây là ảnh giấy tờ tùy thân. Hãy trích xuất và chỉ trả về DUY NHẤT Họ và Tên (Full Name) của người trên giấy tờ. 
Không giải thích thêm, không có dấu ngoặc kép, không dùng markdown. 
Nếu hình ảnh bị mờ hoặc không tìm thấy tên hợp lệ, hãy trả về chữ 'KHÔNG ĐỌC ĐƯỢC'.
''';

    final dio = Dio();
    dio.options.connectTimeout = const Duration(seconds: 6);
    dio.options.receiveTimeout = const Duration(seconds: 15);

    // Danh sách các mô hình Flash tốc độ siêu nhanh (Không dùng bản Pro nặng)
    final modelCandidates = [
      'gemini-1.5-flash-latest',
      'gemini-1.5-flash-002',
      'gemini-1.5-flash-001',
      'gemini-1.5-flash',
      'gemini-2.0-flash-lite-preview-02-05',
    ];

    final errors = <String>[];

    for (final model in modelCandidates) {
      try {
        final singleModelStopwatch = Stopwatch()..start();
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
            ],
            "generationConfig": {
              "temperature": 0.1,
              "maxOutputTokens": 256
            }
          },
        );

        singleModelStopwatch.stop();

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
                  apiStopwatch.stop();
                  debugPrint('🎉 [BENCHMARK REST API] Thành công với model $model trong ${singleModelStopwatch.elapsedMilliseconds} ms -> $resultText');
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
        debugPrint('AI Service REST: Model $model bị bỏ qua: $errMsg');
        errors.add(errMsg);
      }
    }

    apiStopwatch.stop();

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
