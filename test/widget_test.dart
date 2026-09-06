import 'package:flutter_test/flutter_test.dart';

import 'package:mrpizza/app.dart';

void main() {
  testWidgets('App boots to the mock login screen', (WidgetTester tester) async {
    await tester.pumpWidget(const MrPizzaApp());

    expect(find.text('Welcome to Login Screen'), findsOneWidget);
    expect(find.text('Mock Login'), findsOneWidget);
  });
}