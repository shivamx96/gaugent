import XCTest
import GaugentCore
@testable import Gaugent

final class MenuBarPresentationTests: XCTestCase {
    func testAntigravityHasGoogleLabelAndBadge() {
        let value = ProviderUsage(id: "antigravity", name: "Antigravity", windows: reading().windows,
                                  updatedAt: now, condition: .ready)
        XCTAssertTrue(presentation(value, at: now).toolTip.contains("Google · Antigravity"))
        let icon = GaugentIconRenderer.menuBarIcon(providerID: "antigravity", remaining: 0.17)
        XCTAssertEqual(icon.accessibilityDescription, "gaugent, Google")
        XCTAssertEqual(icon.size.width, 20)
    }

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

    func testUsableProviderWinsOverBlockedProviderAndTooltipKeepsWindowDetails() {
        let available = reading()
        let state = UsageOverview(providers: [reading(blocked: true),
            ProviderUsage(id: "codex", name: "Codex", windows: available.windows,
                          updatedAt: now, condition: .ready)], now: now)
        let result = MenuBarPresentation(overview: state, hasEnabledProviders: true,
            displayMode: .glyphAndPercent, dimWhenIdle: true, shortcutRegistered: true)
        XCTAssertEqual(result.providerID, "codex")
        XCTAssertEqual(result.title, " 17%")
        XCTAssertTrue(result.toolTip.contains("Codex · Weekly · 17% remaining · resets"))
        XCTAssertTrue(result.toolTip.contains("Test · limit reached"))
        XCTAssertTrue(result.accessibilityLabel.contains("lowest usable allowance"))
    }

    func testProviderSwitchWithSamePercentageChangesPresentation() {
        let first = reading()
        let second = ProviderUsage(id: "codex", name: "Codex", windows: first.windows,
                                   updatedAt: now, condition: .ready)
        let a = presentation(first, at: now)
        let b = presentation(second, at: now)
        XCTAssertEqual(a.title, b.title)
        XCTAssertEqual(a.remainingFraction, b.remainingFraction)
        XCTAssertNotEqual(a.providerID, b.providerID)
        XCTAssertNotEqual(a, b)
    }

    func testPositiveFractionIsNotRoundedToZeroAndZeroIsBlocked() {
        var value = reading()
        value.windows = [UsageWindow(label: "5-hour", remainingPercent: 0.4, resetsAt: nil)]
        XCTAssertEqual(presentation(value, at: now).title, " <1%")
        XCTAssertTrue(presentation(value, at: now).accessibilityLabel.contains("less than 1 percent"))
        value.windows = [UsageWindow(label: "5-hour", remainingPercent: 0, resetsAt: nil)]
        let blocked = presentation(value, at: now)
        XCTAssertEqual(blocked.title, " !")
        XCTAssertNil(blocked.remainingFraction)
        XCTAssertEqual(blocked.providerID, "test")
        let stale = presentation(value, at: now.addingTimeInterval(601))
        XCTAssertNil(stale.providerID)
        XCTAssertEqual(stale.title, "")
    }

    func testUnrepresentableCachedResetDoesNotReachDateFormatter() {
        var value = reading()
        for seconds in [1e100, Double.infinity, Double.nan] {
            value.windows = [UsageWindow(label: "Weekly", remainingPercent: 17,
                                         resetsAt: Date(timeIntervalSince1970: seconds))]
            XCTAssertTrue(presentation(value, at: now).toolTip.contains("reset time unavailable"),
                          "Invalid reset: \(seconds)")
        }
    }
}
