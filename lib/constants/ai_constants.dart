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
}
