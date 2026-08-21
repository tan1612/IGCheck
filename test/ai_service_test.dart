import 'package:flutter_test/flutter_test.dart';
import 'package:igcheck/constants/ai_constants.dart';
import 'package:igcheck/services/ai_service.dart';

void main() {
  test('AIService singleton instance creation', () {
    final aiService1 = AIService();
    final aiService2 = AIService();
    expect(aiService1, equals(aiService2));
  });

  test('AIService handles unconfigured API key gracefully', () async {
    final aiService = AIService();
    final result = await aiService.extractNameFromImageUrl('https://example.com/sample.jpg');
    // Without GEMINI_API_KEY environment variable, should safely return null
    expect(result, isNull);
  });

  test('AIConstants timeout configurations meet requirement thresholds', () {
    expect(AIConstants.geminiApiConnectTimeout.inSeconds, greaterThanOrEqualTo(15));
    expect(AIConstants.geminiApiConnectTimeout.inSeconds, lessThanOrEqualTo(20));

    expect(AIConstants.geminiApiSendTimeout.inSeconds, greaterThanOrEqualTo(30));
    expect(AIConstants.geminiApiSendTimeout.inSeconds, lessThanOrEqualTo(60));

    expect(AIConstants.geminiApiReceiveTimeout.inSeconds, greaterThanOrEqualTo(30));
    expect(AIConstants.geminiApiReceiveTimeout.inSeconds, lessThanOrEqualTo(60));

    expect(AIConstants.timeoutErrorMessage, contains('Kết nối mạng chậm, vui lòng thử lại'));
    expect(AIConstants.networkErrorMessage, contains('vui lòng thử lại'));
  });
}

