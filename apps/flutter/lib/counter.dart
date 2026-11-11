/// Pure business logic, unit tested without widgets.
class Counter {
  const Counter([this.value = 0]);

  final int value;

  Counter increment() => Counter(value + 1);
  Counter decrement() => Counter(value > 0 ? value - 1 : 0);
  Counter reset() => const Counter();

  String get label => 'Count: $value';
}
