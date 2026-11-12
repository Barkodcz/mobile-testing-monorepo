import 'package:flutter/material.dart';

import 'counter.dart';

void main() => runApp(const CounterApp());

class CounterApp extends StatelessWidget {
  const CounterApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      debugShowCheckedModeBanner: false,
      home: CounterScreen(),
    );
  }
}

class CounterScreen extends StatefulWidget {
  const CounterScreen({super.key});

  @override
  State<CounterScreen> createState() => _CounterScreenState();
}

class _CounterScreenState extends State<CounterScreen> {
  Counter _counter = const Counter();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Text(
              _counter.label,
              key: const Key('count_label'),
              style: Theme.of(context).textTheme.headlineLarge,
            ),
            const SizedBox(height: 24),
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Flexible(
                  child: FilledButton(
                    key: const Key('decrement_button'),
                    onPressed: () => setState(() => _counter = _counter.decrement()),
                    child: const Text('Decrement'),
                  ),
                ),
                const SizedBox(width: 16),
                Flexible(
                  child: FilledButton(
                    key: const Key('increment_button'),
                    onPressed: () => setState(() => _counter = _counter.increment()),
                    child: const Text('Increment'),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            OutlinedButton(
              key: const Key('reset_button'),
              onPressed: () => setState(() => _counter = _counter.reset()),
              child: const Text('Reset'),
            ),
          ],
        ),
      ),
    );
  }
}
