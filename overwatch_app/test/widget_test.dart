import 'package:flutter_test/flutter_test.dart';
import 'package:overwatch_app/main.dart';

void main() {
  testWidgets('Overwatch smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const OverwatchApp());
    await tester.pump();
  });
}
