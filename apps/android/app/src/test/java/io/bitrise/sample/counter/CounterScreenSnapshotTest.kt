package io.bitrise.sample.counter

import androidx.compose.material3.MaterialTheme
import app.cash.paparazzi.DeviceConfig
import org.junit.Rule
import org.junit.Test

/**
 * Paparazzi snapshot test: renders the screen on the JVM (no emulator).
 * Record:  ./gradlew :app:recordPaparazziDebug   (writes app/src/test/snapshots/)
 * Verify:  ./gradlew :app:verifyPaparazziDebug
 *
 * Uses bitrisePaparazzi() (see BitrisePaparazzi.kt) instead of the plain
 * Paparazzi rule so a failing snapshot's diff image is named and placed per
 * Bitrise's attachment convention and shows up on the test's Tests tab entry.
 */
class CounterScreenSnapshotTest {
    @get:Rule
    val paparazzi = bitrisePaparazzi(deviceConfig = DeviceConfig.PIXEL_5)

    @Test
    fun counterScreenDefault() {
        paparazzi.snapshot { MaterialTheme { CounterScreen() } }
    }
}
