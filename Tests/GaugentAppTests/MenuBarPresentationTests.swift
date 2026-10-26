import XCTest
import GaugentCore
@testable import Gaugent

final class MenuBarPresentationTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_000_000)

    private func reading(resetAfter: TimeInterval = 3600, blocked: Bool = false) -> ProviderUsage {
        ProviderUsage(id: "test", name: "Test", installed: true, authenticated: true,
            windows: [UsageWindow(label: "Weekly", remainingPercent: 17, resetsAt: now.addingTimeInterval(resetAfter))],
            updatedAt: now, condition: .ready, limitReached: blocked)
    }

    private func presentation(_ reading: ProviderUsage, at date: Date,
                              mode: MenuBarDisplayMode = .glyphAndPercent,
                              dim: Bool = true, shortcut: Bool = true) -> MenuBarPresentation {
        MenuBarPresentation(overview: UsageOverview(providers: [reading], now: date), hasEnabledProviders: true,
            displayMode: mode, dimWhenIdle: dim, shortcutRegistered: shortcut)
    }

    func testClockTicksDoNotChangePresentationUntilReadingBecomesStale() {
        let reading = reading()
        let initial = presentation(reading, at: now)
        XCTAssertEqual(initial, presentation(reading, at: now.addingTimeInterval(15)))
        XCTAssertEqual(initial, presentation(reading, at: now.addingTimeInterval(600)))
        let stale = presentation(reading, at: now.addingTimeInterval(601))
        XCTAssertNotEqual(initial, stale)
        XCTAssertNil(stale.remainingFraction)
        XCTAssertEqual(stale.title, "")
        XCTAssertEqual(stale.alpha, 0.58)
    }

    func testWindowExpiryAndBlockExpiryStillUpdateStatus() {
        let reading = reading(resetAfter: 60)
        XCTAssertEqual(presentation(reading, at: now).title, " 17%")
        XCTAssertEqual(presentation(reading, at: now.addingTimeInterval(60)).title, "")
        let blocked = self.reading(blocked: true)
        XCTAssertEqual(presentation(blocked, at: now).title, " !")
        XCTAssertEqual(presentation(blocked, at: now.addingTimeInterval(601)).title, "")
    }

    func testPreferencesAndShortcutChangePresentationWithoutChangingNeedle() {
        let reading = reading()
        let initial = presentation(reading, at: now)
        let glyph = presentation(reading, at: now, mode: .glyph)
        XCTAssertNotEqual(initial, glyph)
        XCTAssertEqual(initial.remainingFraction, glyph.remainingFraction)
        XCTAssertEqual(glyph.title, "")
        XCTAssertNotEqual(initial, presentation(reading, at: now, shortcut: false))
        let stale = presentation(reading, at: now.addingTimeInterval(601), dim: false)
        XCTAssertEqual(stale.alpha, 1)
    }
}
