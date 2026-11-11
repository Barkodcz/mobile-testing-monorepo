package io.bitrise.sample.counter

import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Button
import androidx.compose.material3.MaterialTheme
import androidx.compose.material3.OutlinedButton
import androidx.compose.material3.Surface
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp

class MainActivity : ComponentActivity() {
    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        setContent { MaterialTheme { CounterScreen() } }
    }
}

@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun CounterScreen() {
    var counter by remember { mutableStateOf(Counter()) }

    Surface(
        // Exposes testTags as resource-ids so Maestro and Appium can find them.
        modifier = Modifier.fillMaxSize().semantics { testTagsAsResourceId = true },
    ) {
        Column(
            verticalArrangement = Arrangement.spacedBy(24.dp, Alignment.CenterVertically),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            Text(
                text = counter.label,
                style = MaterialTheme.typography.headlineLarge,
                modifier = Modifier.testTag("count_label"),
            )
            Row(horizontalArrangement = Arrangement.spacedBy(16.dp)) {
                Button(
                    onClick = { counter = counter.decrement() },
                    modifier = Modifier.testTag("decrement_button"),
                ) { Text("Decrement") }
                Button(
                    onClick = { counter = counter.increment() },
                    modifier = Modifier.testTag("increment_button"),
                ) { Text("Increment") }
            }
            OutlinedButton(
                onClick = { counter = counter.reset() },
                modifier = Modifier.testTag("reset_button"),
            ) { Text("Reset") }
        }
    }
}
