// Unit tests: plain functions, no rendering.
import { decrement, formatCount, increment } from '../src/counter';

describe('counter logic', () => {
  test('increment adds one', () => {
    expect(increment(0)).toBe(1);
  });

  test('decrement never goes below zero', () => {
    expect(decrement(0)).toBe(0);
    expect(decrement(3)).toBe(2);
  });

  test('formatCount builds the label', () => {
    expect(formatCount(5)).toBe('Count: 5');
  });
});
