import 'package:flutter_test/flutter_test.dart';
import 'package:igcheck/app.dart';

void main() {
  testWidgets('App initialization test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(const IGCheckApp());

    // Verify that Splash screen title or logo is rendered
    expect(find.text('IGCheck'), findsOneWidget);
  });
}
