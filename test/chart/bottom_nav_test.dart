import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:drezafx/screens/common/dz_widgets.dart';

void main() {
  testWidgets('DzBottomNav shows 4 items and fires callbacks', (tester) async {
    var home = 0, chart = 0, history = 0, settings = 0;

    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: DzBottomNav(
            currentIndex: 1,
            onHome: () => home++,
            onChart: () => chart++,
            onHistory: () => history++,
            onSettings: () => settings++,
          ),
        ),
      ),
    );

    expect(find.text('Home'), findsOneWidget);
    expect(find.text('Chart'), findsOneWidget);
    expect(find.text('History'), findsOneWidget);
    expect(find.text('Settings'), findsOneWidget);

    await tester.tap(find.text('Home'));
    await tester.tap(find.text('Chart'));
    await tester.tap(find.text('History'));
    await tester.tap(find.text('Settings'));
    await tester.pump();

    expect(home, 1);
    expect(chart, 1);
    expect(history, 1);
    expect(settings, 1);
  });
}
