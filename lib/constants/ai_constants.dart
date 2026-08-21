class AIConstants {
  /// Model mặc định nhanh nhất, rẻ nhất cho tác vụ OCR đọc họ tên từ ảnh giấy tờ
  static const String primaryModel = 'gemini-flash-lite-latest';

  /// Model dự phòng nếu cần độ chính xác cao hơn
  static const String fallbackModel = 'gemini-flash-latest';

  /// Danh sách các alias model chính thức được hỗ trợ (sử dụng đuôi -latest để luôn trỏ tới bản ổn định mới nhất)
  static const List<String> modelCandidates = [
    primaryModel,
    fallbackModel,
  ];

  /// Thời gian tối đa thiết lập kết nối tới Gemini API (15-20 giây)
  static const Duration geminiApiConnectTimeout = Duration(seconds: 20);

  /// Thời gian tối đa upload dữ liệu/ảnh lên Gemini API (30-60 giây)
  static const Duration geminiApiSendTimeout = Duration(seconds: 45);

  /// Thời gian tối đa chờ Gemini API xử lý ảnh và trả kết quả (30-60 giây)
  static const Duration geminiApiReceiveTimeout = Duration(seconds: 45);

  /// Thông báo lỗi thân thiện bằng tiếng Việt khi bị timeout (quá thời gian chờ)
  static const String timeoutErrorMessage = 'LỖI_TIMEOUT: Kết nối mạng chậm, vui lòng thử lại.';

  /// Thông báo lỗi thân thiện bằng tiếng Việt khi không có kết nối mạng
  static const String networkErrorMessage = 'LỖI_NETWORK: Kết nối mạng không ổn định, vui lòng thử lại.';
}

