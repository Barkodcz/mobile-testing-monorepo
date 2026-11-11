// Patrol tests: Flutter finders ($) plus native OS interactions ($.platform.mobile).
// Run with: patrol test            (all files in patrol_test/)
//           patrol test --target patrol_test/counter_patrol_test.dart
import 'package:counter_flutter/main.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:patrol/patrol.dart';

void main() {
  patrolTest('counter keeps its value after going to the home screen', ($) async {
    await $.pumpWidgetAndSettle(const CounterApp());
    expect($('Count: 0'), findsOneWidget);

    // #increment_button finds the widget with Key('increment_button').
    await $(#increment_button).tap();
    await $(#increment_button).tap();
    expect($('Count: 2'), findsOneWidget);

    // Native: leave the app and come back. Plain integration_test can't do this.
    await $.platform.mobile.pressHome();
    await $.platform.mobile.openApp();
    expect($('Count: 2'), findsOneWidget);

    await $(#reset_button).tap();
    expect($('Count: 0'), findsOneWidget);
  });

  patrolTest('notification shade can be opened over the app', ($) async {
    await $.pumpWidgetAndSettle(const CounterApp());

    await $.platform.mobile.openNotifications();
    await $.platform.mobile.closeNotifications();

    await $('Increment').tap(); // find by visible text
    expect($('Count: 1'), findsOneWidget);
  });
}
