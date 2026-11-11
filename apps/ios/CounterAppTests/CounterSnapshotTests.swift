// Snapshot test with swift-snapshot-testing (XCTest-based).
// First run records the reference image into __Snapshots__/ and FAILS on purpose.
// Commit the image, then later runs compare against it.
// Record on the same simulator model + iOS version that CI uses (iPhone 16).
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
