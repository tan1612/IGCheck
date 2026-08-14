import 'package:flutter_test/flutter_test.dart';
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
}
