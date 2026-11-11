package io.bitrise.sample.counter

import androidx.compose.material3.MaterialTheme
import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.Paparazzi
import org.junit.Rule
import org.junit.Test

/**
 * Paparazzi snapshot test: renders the screen on the JVM (no emulator).
 * Record:  ./gradlew :app:recordPaparazziDebug   (writes app/src/test/snapshots/)
 * Verify:  ./gradlew :app:verifyPaparazziDebug
 */
class CounterScreenSnapshotTest {
    @get:Rule
    val paparazzi = Paparazzi(deviceConfig = DeviceConfig.PIXEL_5)

    @Test
    fun counterScreenDefault() {
        paparazzi.snapshot { MaterialTheme { CounterScreen() } }
    }
}
