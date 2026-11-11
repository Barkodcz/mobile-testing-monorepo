// Widget (UI) tests: render widgets in a test environment, no device needed.
// Keep this file name: `flutter create .` only adds a default widget_test.dart when it is missing.
import 'package:counter_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('starts at zero', (tester) async {
    await tester.pumpWidget(const CounterApp());
    expect(find.text('Count: 0'), findsOneWidget);
  });

  testWidgets('increment, decrement and reset update the label', (tester) async {
    await tester.pumpWidget(const CounterApp());

    await tester.tap(find.byKey(const Key('increment_button')));
    await tester.tap(find.byKey(const Key('increment_button')));
    await tester.pump();
    expect(find.text('Count: 2'), findsOneWidget);

    await tester.tap(find.byKey(const Key('decrement_button')));
    await tester.pump();
    expect(find.text('Count: 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reset_button')));
    await tester.pump();
    expect(find.text('Count: 0'), findsOneWidget);
  });
}
