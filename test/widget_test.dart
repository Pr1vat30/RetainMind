import 'package:flutter_test/flutter_test.dart';
import 'package:retain_mind_def/constants.dart';
import 'package:retain_mind_def/main.dart';

void main() {
  testWidgets('RetainMind app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const RetainMindApp());
    expect(find.text(AppConstants.appTitle), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 700));
    await tester.pump(const Duration(milliseconds: 1800));
    await tester.pump(const Duration(milliseconds: 600));
  });
}
