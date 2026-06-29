import 'package:flutter_test/flutter_test.dart';
import 'package:triplesapp/main.dart';

void main() {
  testWidgets('App builds', (WidgetTester tester) async {
    await tester.pumpWidget(const OneOfOneApp());
    await tester.pump();
  });
}
