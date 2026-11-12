package io.bitrise.sample.counter

import app.cash.paparazzi.DeviceConfig
import app.cash.paparazzi.HtmlReportWriter
import app.cash.paparazzi.Paparazzi
import app.cash.paparazzi.Snapshot
import app.cash.paparazzi.SnapshotHandler
import app.cash.paparazzi.SnapshotVerifier
import java.awt.image.BufferedImage
import java.io.File
import javax.imageio.ImageIO

// Writes Paparazzi's rendered frames using Bitrise's attachment naming
// convention (<classname>__<name>__<label>.<ext>), in addition to the
// normal HTML report / verifier, so a failing snapshot's diff image shows up
// attached to its test case on the Tests tab.
// https://docs.bitrise.io/en/bitrise-ci/testing/test-reports/test-attachments/naming-attachments-after-test-cases

private fun clean(value: String) = value.replace(Regex("""["*/:<>?\\|]"""), "_")

fun bitrisePaparazzi(deviceConfig: DeviceConfig = DeviceConfig.PIXEL_5) =
    Paparazzi(deviceConfig = deviceConfig, snapshotHandler = BitriseSnapshotHandler())

class BitriseSnapshotHandler(
    maxPercentDifference: Double = 0.1,
    private val delegate: SnapshotHandler =
        if (System.getProperty("paparazzi.test.verify") == "true") SnapshotVerifier(maxPercentDifference)
        else HtmlReportWriter(),
) : SnapshotHandler by delegate {
    override fun newFrameHandler(snapshot: Snapshot, frameCount: Int, fps: Int): SnapshotHandler.FrameHandler {
        val frames = delegate.newFrameHandler(snapshot, frameCount, fps)
        val test = snapshot.testName
        val label = snapshot.name?.replace(Regex("_+"), "_")?.removePrefix("_") ?: "snapshot"
        val name = "${clean("${test.packageName}.${test.className}")}__${clean(test.methodName)}__$label"
        val file = File(
            System.getProperty("paparazzi.build.dir"),
            "bitrise-snapshots/${System.getProperty("bitrise.test.task")}/$name.png",
        )
        return object : SnapshotHandler.FrameHandler by frames {
            override fun handle(image: BufferedImage) {
                file.parentFile.mkdirs()
                ImageIO.write(image, "png", file)
                frames.handle(image)
            }
        }
    }
}
