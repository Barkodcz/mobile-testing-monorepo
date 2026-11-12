// Classic XCTest unit tests, covering the same areas as CounterTests.swift
// (Swift Testing) -- added to demonstrate both frameworks coexisting in the
// same test target/scheme. CounterTests.swift is untouched.
import XCTest
@testable import CounterApp

final class CounterXCTests: XCTestCase {
    func testStartsAtZero() {
        XCTAssertEqual(Counter().value, 0)
    }

    func testIncrementAddsOne() {
        var counter = Counter()
        counter.increment()
        XCTAssertEqual(counter.value, 1)
    }

    func testDecrementNeverGoesBelowZero() {
        var counter = Counter()
        counter.decrement()
        XCTAssertEqual(counter.value, 0)
    }

    func testLabelShowsValue() {
        var counter = Counter()
        for _ in 0..<3 { counter.increment() }
        XCTAssertEqual(counter.label, "Count: 3")
    }

    func testReset() {
        var counter = Counter()
        counter.increment()
        counter.increment()
        counter.reset()
        XCTAssertEqual(counter.value, 0)
    }
}
