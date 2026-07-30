import 'package:flutter_test/flutter_test.dart';

import 'package:backend_f/main.dart';

void main() {
  testWidgets('Food and water test app opens', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(const LogCkdTestApp());
    await tester.pump();

    expect(find.text('Food & Water Test'), findsOneWidget);
  });
}
