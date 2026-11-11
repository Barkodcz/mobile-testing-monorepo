// Golden (snapshot) test. Record references with:
//   flutter test --update-goldens test/goldens
// Record on the same OS as CI (Linux), e.g. with the flutter_record_goldens workflow.
@Tags(['golden'])
library;

import 'package:counter_flutter/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('counter screen golden', (tester) async {
    tester.view.physicalSize = const Size(1080, 1920);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const CounterApp());
    await expectLater(find.byType(CounterApp), matchesGoldenFile('counter_screen.png'));
  });
}
