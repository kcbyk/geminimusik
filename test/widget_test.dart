import 'package:flutter_test/flutter_test.dart';
import 'package:ai_music_hub/main.dart';

void main() {
  testWidgets('App smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const GeminiApp());
    expect(find.byType(GeminiApp), findsOneWidget);
  });
}
