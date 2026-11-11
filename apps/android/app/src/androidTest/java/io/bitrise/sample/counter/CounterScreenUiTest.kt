package io.bitrise.sample.counter

import androidx.compose.ui.test.assertTextEquals
import androidx.compose.ui.test.junit4.createAndroidComposeRule
import androidx.compose.ui.test.onNodeWithTag
import androidx.compose.ui.test.performClick
import androidx.test.ext.junit.runners.AndroidJUnit4
import org.junit.Rule
import org.junit.Test
import org.junit.runner.RunWith

/** Instrumented Compose UI tests: run on an emulator with `./gradlew connectedDebugAndroidTest`. */
@RunWith(AndroidJUnit4::class)
class CounterScreenUiTest {
    @get:Rule
    val rule = createAndroidComposeRule<MainActivity>()

    @Test
    fun startsAtZero() {
        rule.onNodeWithTag("count_label").assertTextEquals("Count: 0")
    }

    @Test
    fun incrementDecrementReset() {
        rule.onNodeWithTag("increment_button").performClick()
        rule.onNodeWithTag("increment_button").performClick()
        rule.onNodeWithTag("count_label").assertTextEquals("Count: 2")

        rule.onNodeWithTag("decrement_button").performClick()
        rule.onNodeWithTag("count_label").assertTextEquals("Count: 1")

        rule.onNodeWithTag("reset_button").performClick()
        rule.onNodeWithTag("count_label").assertTextEquals("Count: 0")
    }
}
