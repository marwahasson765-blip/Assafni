import 'package:flutter_test/flutter_test.dart';
import 'package:asaafni/main.dart';
void main(){test('password hashing is deterministic and not plaintext',(){expect(hash('123456'),isNot('123456'));expect(hash('123456'),hash('123456'));});testWidgets('splash has app name',(tester)async{await tester.pumpWidget(const AsaafniApp());expect(find.text('أسعفني Asaafni'),findsOneWidget);await tester.pump(const Duration(milliseconds:901));});}
