// Unit tests written with Swift Testing (Xcode 16+).
import Testing
@testable import CounterApp

struct CounterTests {
    @Test func startsAtZero() {
        #expect(Counter().value == 0)
    }

    @Test func incrementAddsOne() {
        var counter = Counter()
        counter.increment()
        #expect(counter.value == 1)
    }

    @Test func decrementNeverGoesBelowZero() {
        var counter = Counter()
        counter.decrement()
        #expect(counter.value == 0)
    }

    @Test(arguments: [0, 1, 42])
    func labelShowsValue(times: Int) {
        var counter = Counter()
        for _ in 0..<times { counter.increment() }
        #expect(counter.label == "Count: \(times)")
    }
}
