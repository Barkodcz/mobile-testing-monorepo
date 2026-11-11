// Pure business logic: easy to unit test without rendering anything.
export function increment(value: number): number {
  return value + 1;
}

export function decrement(value: number): number {
  return Math.max(0, value - 1);
}

export function formatCount(value: number): string {
  return `Count: ${value}`;
}
