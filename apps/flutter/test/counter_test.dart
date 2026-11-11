// Unit tests: plain Dart, no widgets.
import 'package:counter_flutter/counter.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('Counter', () {
    test('starts at zero', () => expect(const Counter().value, 0));
    test('increment adds one', () => expect(const Counter().increment().value, 1));
    test('decrement never goes below zero', () => expect(const Counter().decrement().value, 0));
    test('label shows value', () => expect(const Counter(3).label, 'Count: 3'));
  });
}
