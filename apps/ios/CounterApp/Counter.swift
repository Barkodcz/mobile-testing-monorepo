// Pure business logic, unit tested without any UI.
struct Counter: Equatable {
    private(set) var value = 0

    mutating func increment() { value += 1 }
    mutating func decrement() { value = max(0, value - 1) }
    mutating func reset() { value = 0 }

    var label: String { "Count: \(value)" }
}
