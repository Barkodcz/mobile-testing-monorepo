package io.bitrise.sample.counter

/** Pure business logic, unit tested on the JVM. */
data class Counter(val value: Int = 0) {
    fun increment() = copy(value = value + 1)
    fun decrement() = copy(value = maxOf(0, value - 1))
    fun reset() = Counter()
    val label: String get() = "Count: $value"
}
