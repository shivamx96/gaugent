import XCTest
@testable import Gaugent

final class UpdateDriverTests: XCTestCase {
    @MainActor
    func testFailureDiscardsDownloadCancellation() {
        var states: [UpdateState] = []
        let driver = UpdateDriver { states.append($0) }
        var cancellations = 0
        var acknowledgements = 0
        driver.showDownloadInitiated { cancellations += 1 }
        driver.showUpdaterError(NSError(domain: "Test", code: 1)) { acknowledgements += 1 }
        driver.dismiss()
        XCTAssertEqual(cancellations, 0)
        XCTAssertEqual(acknowledgements, 1)
        XCTAssertEqual(states.last, .idle)
    }

    @MainActor
    func testDismissCancelsDownloadOnlyOnce() {
        let driver = UpdateDriver { _ in }
        var cancellations = 0
        driver.showDownloadInitiated { cancellations += 1 }
        driver.dismiss()
        driver.dismiss()
        XCTAssertEqual(cancellations, 1)
    }

    @MainActor
    func testUnconfiguredUpdaterDoesNotStart() {
        let updates = UpdateController(startAutomatically: false)
        XCTAssertFalse(updates.isAvailable)
        updates.checkForUpdates()
        XCTAssertEqual(updates.state, .idle)
    }
}
