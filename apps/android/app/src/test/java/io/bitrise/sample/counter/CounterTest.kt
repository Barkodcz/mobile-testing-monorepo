package io.bitrise.sample.counter

import org.junit.Assert.assertEquals
import org.junit.Test

/** Local unit tests: run on the JVM with `./gradlew testDebugUnitTest`. */
class CounterTest {
    @Test
    fun startsAtZero() {
        assertEquals(0, Counter().value)
    }

    @Test
    fun incrementAddsOne() {
        assertEquals(1, Counter().increment().value)
    }

    @Test
    fun decrementNeverGoesBelowZero() {
        assertEquals(0, Counter().decrement().value)
    }

    @Test
    fun labelShowsValue() {
        assertEquals("Count: 2", Counter().increment().increment().label)
    }
}
