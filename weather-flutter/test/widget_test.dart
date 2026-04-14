import 'package:flutter_test/flutter_test.dart';

import 'package:weather_display/main.dart';

void main() {
  testWidgets('Weather app smoke test', (WidgetTester tester) async {
    await tester.pumpWidget(const WeatherApp());
    // App should render without errors
    expect(find.byType(WeatherApp), findsOneWidget);
  });
}
