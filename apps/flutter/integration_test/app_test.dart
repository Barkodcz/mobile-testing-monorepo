// Integration test: runs the full app on an emulator/simulator.
//   flutter test integration_test -d <device-id>
import 'package:counter_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('user can count up and reset', (tester) async {
    await tester.pumpWidget(const CounterApp());
    await tester.pumpAndSettle();

    await tester.tap(find.byKey(const Key('increment_button')));
    await tester.pumpAndSettle();
    expect(find.text('Count: 1'), findsOneWidget);

    await tester.tap(find.byKey(const Key('reset_button')));
    await tester.pumpAndSettle();
    expect(find.text('Count: 0'), findsOneWidget);
  });
}
