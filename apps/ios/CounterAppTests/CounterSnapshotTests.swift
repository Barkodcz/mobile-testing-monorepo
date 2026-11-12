// Snapshot test with swift-snapshot-testing (XCTest-based).
// First run records the reference image into __Snapshots__/ and FAILS on purpose.
// Commit the image, then later runs compare against it.
// .image(on: .iPhone13) is swift-snapshot-testing's own synthetic device
// trait -- rendering is independent of whichever simulator CI actually
// boots, so the recorded reference stays valid across CI simulator changes.
import SnapshotTesting
import SwiftUI
import XCTest
@testable import CounterApp

final class CounterSnapshotTests: XCTestCase {
    func testCounterViewDefault() {
        let controller = UIHostingController(rootView: CounterView())
        assertSnapshot(of: controller, as: .image(on: .iPhone13))
    }
}
