import 'dart:convert';
import 'package:dio/dio.dart';
import 'package:flutter_image_compress/flutter_image_compress.dart';
import 'package:flutter/foundation.dart';
import 'package:igcheck/constants/ai_constants.dart';
import '../models/document_profile_name.dart';

class AIService {
  // Đọc API Key bảo mật từ Environment Variables
  static const String _buildApiKey = String.fromEnvironment(
    'GEMINI_API_KEY',
    defaultValue: '',
  );
  String? _sessionApiKey;
  String get _apiKey => _sessionApiKey ?? _buildApiKey;

  /// Optional session-only key; never written to a file or WebView storage.
  void setApiKeyForSession(String value) {
    _sessionApiKey = value.trim().isEmpty ? null : value.trim();
  }

  static final AIService _instance = AIService._internal();
  factory AIService() => _instance;
  AIService._internal() {
    if (_apiKey.isEmpty || _apiKey == 'NHET_KEY_CUA_NI_VAO_DAY') {
      debugPrint('⚠️ AI Service: Chưa cấu hình GEMINI_API_KEY!');
    } else {
      final masked = _apiKey.length > 8
          ? '${_apiKey.substring(0, 4)}...${_apiKey.substring(_apiKey.length - 4)}'
          : '***';
      debugPrint(
        '🚀 AI Service: Đã tải thành công API Key từ Environment: $masked',
      );
    }
  }

  bool get isConfigured =>
      _apiKey.isNotEmpty && _apiKey != 'NHET_KEY_CUA_NI_VAO_DAY';

  /// Reads the selected document directly, without uploading it to file hosting.
  Future<String?> extractNameFromImageBytes(Uint8List bytes) async {
    if (!isConfigured) return null;
    if (bytes.isEmpty) return 'LỖI: Ảnh giấy tờ đang trống.';
    final compressed = await _compressAndResizeImage(bytes);
    return _callGeminiRestApi(compressed);
  }

  Future<DocumentProfileName> extractProfileNameFromDocument(
    Uint8List bytes,
  ) async {
    if (!isConfigured) {
      throw StateError('Chưa cấu hình GEMINI_API_KEY cho bản build này.');
    }
    if (bytes.isEmpty) throw StateError('Chưa chọn ảnh giấy tờ.');
    final compressed = await _compressAndResizeImage(bytes);
    final text = await _callGeminiRestApi(
      compressed,
      jsonResponse: true,
      customPrompt:
          '''Đọc HỌ TÊN của chủ giấy tờ trong ảnh. Chỉ đọc chữ trên giấy tờ, không nhận diện người từ khuôn mặt.
Trả JSON: {"fullName":"họ tên đúng thứ tự trên giấy tờ","givenName":"tên riêng","middleName":"tên đệm hoặc chuỗi rỗng","familyName":"họ","confidence":0.0}.
Giữ nguyên dấu và chữ của tên. Dựa vào nhãn surname/given name nếu có; với họ tên Việt Nam, họ đứng đầu và tên riêng đứng cuối.
Không trả số giấy tờ, ngày sinh, địa chỉ hoặc thông tin khác. Không suy đoán chữ bị mờ.
Nếu không đọc rõ hoặc không tách được họ và tên, trả confidence dưới 0.9 và các trường không xác định là chuỗi rỗng.''',
    );
    if (text == null || text.startsWith('LỖI') || text == 'KHÔNG ĐỌC ĐƯỢC') {
      throw StateError(text ?? 'Không đọc được họ tên trên giấy tờ.');
    }
    try {
      return DocumentProfileName.fromJson(
        jsonDecode(text) as Map<String, dynamic>,
      );
    } on FormatException {
      rethrow;
    } catch (_) {
      throw const FormatException('AI chưa trả về họ tên hợp lệ.');
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
        debugPrint(
          '⚡ [BENCHMARK] Nén & Resize ảnh xong trong ${compressStopwatch.elapsedMilliseconds} ms (Từ ${(bytes.length / 1024 / 1024).toStringAsFixed(2)}MB -> ${(result.length / 1024).toStringAsFixed(1)}KB)',
        );
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
    if (!isConfigured) {
      debugPrint('AI Service: Chưa cấu hình Gemini API Key.');
      return null;
    }

    final totalStopwatch = Stopwatch()..start();
    try {
      final rawBytes = await imageFile.readAsBytes();
      final compressedBytes = await _compressAndResizeImage(rawBytes);

      final result = await _callGeminiRestApi(compressedBytes);
      totalStopwatch.stop();
      debugPrint(
        '⏱️ [BENCHMARK TOTAL] extractNameFromImage kết thúc trong: ${totalStopwatch.elapsedMilliseconds} ms (${(totalStopwatch.elapsedMilliseconds / 1000).toStringAsFixed(2)}s)',
      );
      return result;
    } catch (e) {
      totalStopwatch.stop();
      debugPrint('Lỗi đọc file ảnh: $e');
      return 'LỖI: Không thể đọc file ảnh!';
    }
  }

  /// Gửi ảnh từ URL lên Gemini Vision để trích xuất tên
  Future<String?> extractNameFromImageUrl(String imageUrl) async {
    if (!isConfigured) {
      debugPrint('AI Service: Chưa cấu hình Gemini API Key.');
      return null;
    }

    final totalStopwatch = Stopwatch()..start();
    try {
      final dio = Dio();
      dio.options.connectTimeout = AIConstants.geminiApiConnectTimeout;
      dio.options.sendTimeout = AIConstants.geminiApiSendTimeout;
      dio.options.receiveTimeout = AIConstants.geminiApiReceiveTimeout;
      final responseHttp = await dio.get(
        imageUrl,
        options: Options(responseType: ResponseType.bytes),
      );
      final rawBytes = responseHttp.data as List<int>;
      final compressedBytes = await _compressAndResizeImage(rawBytes);
      final result = await _callGeminiRestApi(compressedBytes);
      totalStopwatch.stop();
      debugPrint(
        '⏱️ [BENCHMARK TOTAL] extractNameFromImageUrl kết thúc trong: ${totalStopwatch.elapsedMilliseconds} ms',
      );
      return result;
    } catch (e) {
      totalStopwatch.stop();
      debugPrint('Lỗi tải ảnh từ URL: $e');
      if (e is DioException &&
          (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout)) {
        return AIConstants.timeoutErrorMessage;
      }
      return 'LỖI: Không thể tải ảnh từ URL!';
    }
  }

  /// Gọi trực tiếp Google Gemini REST API với hằng số model tập trung (AIConstants)
  Future<String?> _callGeminiRestApi(
    List<int> bytes, {
    String? customPrompt,
    bool jsonResponse = false,
  }) async {
    final apiStopwatch = Stopwatch()..start();
    final base64Image = base64Encode(bytes);

    const promptText = '''
Đây là ảnh giấy tờ tùy thân. Hãy trích xuất và chỉ trả về DUY NHẤT Họ và Tên (Full Name) của người trên giấy tờ. 
Không giải thích thêm, không có dấu ngoặc kép, không dùng markdown. 
Nếu hình ảnh bị mờ hoặc không tìm thấy tên hợp lệ, hãy trả về chữ 'KHÔNG ĐỌC ĐƯỢC'.
''';

    final dio = Dio();
    dio.options.connectTimeout = AIConstants.geminiApiConnectTimeout;
    dio.options.sendTimeout = AIConstants.geminiApiSendTimeout;
    dio.options.receiveTimeout = AIConstants.geminiApiReceiveTimeout;

    // Lấy danh sách các model alias mới nhất từ AIConstants tập trung
    final modelCandidates = AIConstants.modelCandidates;

    final errors = <String>[];

    for (final model in modelCandidates) {
      try {
        final singleModelStopwatch = Stopwatch()..start();
        final url =
            'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_apiKey';
        debugPrint('AI Service REST: Đang gọi model $model...');

        final response = await dio.post(
          url,
          options: Options(
            headers: {'Content-Type': 'application/json'},
            connectTimeout: AIConstants.geminiApiConnectTimeout,
            sendTimeout: AIConstants.geminiApiSendTimeout,
            receiveTimeout: AIConstants.geminiApiReceiveTimeout,
          ),
          data: {
            "contents": [
              {
                "parts": [
                  {"text": customPrompt ?? promptText},
                  {
                    "inline_data": {
                      "mime_type":
                          bytes.length > 3 && bytes[0] == 137 && bytes[1] == 80
                          ? "image/png"
                          : "image/jpeg",
                      "data": base64Image,
                    },
                  },
                ],
              },
            ],
            "generationConfig": {
              "temperature": 0.1,
              "maxOutputTokens": jsonResponse ? 512 : 256,
              if (jsonResponse) "responseMimeType": "application/json",
            },
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
                  debugPrint(
                    'AI OCR hoàn tất với model $model trong ${singleModelStopwatch.elapsedMilliseconds} ms',
                  );
                  return resultText;
                }
              }
            }
          }
        }
      } catch (e) {
        String errMsg = '';
        if (e is DioException) {
          if (e.type == DioExceptionType.connectionTimeout ||
              e.type == DioExceptionType.sendTimeout ||
              e.type == DioExceptionType.receiveTimeout ||
              (e.message != null &&
                  e.message!.toLowerCase().contains('took longer than')) ||
              (e.message != null &&
                  e.message!.toLowerCase().contains('timeout'))) {
            errMsg = AIConstants.timeoutErrorMessage;
          } else if (e.type == DioExceptionType.connectionError) {
            errMsg = AIConstants.networkErrorMessage;
          } else {
            final resp = e.response;
            if (resp != null && resp.data != null) {
              final errorData = resp.data;
              if (errorData is Map && errorData['error'] != null) {
                errMsg =
                    errorData['error']['message']?.toString() ??
                    e.message ??
                    e.toString();
              } else {
                errMsg = e.message ?? e.toString();
              }
            } else {
              errMsg = e.message ?? e.toString();
            }
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
      final hasTimeout = errors.any(
        (err) =>
            err == AIConstants.timeoutErrorMessage ||
            err.contains('TIMEOUT') ||
            err.toLowerCase().contains('took longer than'),
      );
      if (hasTimeout) {
        return AIConstants.timeoutErrorMessage;
      }

      final hasNetwork = errors.any(
        (err) =>
            err == AIConstants.networkErrorMessage || err.contains('NETWORK'),
      );
      if (hasNetwork) {
        return AIConstants.networkErrorMessage;
      }

      final first = errors.first;
      if (first.contains('API key not valid') ||
          first.contains('API_KEY_INVALID') ||
          first.contains('invalid API key')) {
        return 'LỖI: Gemini API Key không hợp lệ. Vui lòng kiểm tra lại API Key!';
      }
      if (first.contains('429') ||
          first.contains('quota') ||
          first.contains('RESOURCE_EXHAUSTED')) {
        return 'LỖI: Quá tải hạn ngạch API (Quota Limit), vui lòng thử lại sau 1 phút!';
      }
      return 'LỖI: Kết nối tới AI không thành công, vui lòng thử lại!';
    }

    return 'KHÔNG ĐỌC ĐƯỢC';
  }
}
