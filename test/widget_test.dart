import 'package:flutter_test/flutter_test.dart';
import 'package:asaafni/main.dart';

void main() {
  testWidgets('يعرض التطبيق شاشة البداية', (tester) async {
    await tester.pumpWidget(const AsaafniApp());
    expect(find.text('أسعفني Asaafni'), findsOneWidget);
    await tester.pump(const Duration(milliseconds: 901));
  });
}
