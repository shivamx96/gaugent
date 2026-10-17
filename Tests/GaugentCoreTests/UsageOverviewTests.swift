import XCTest
@testable import GaugentCore

final class UsageOverviewTests: XCTestCase {
    let now = Date(timeIntervalSince1970: 1_700_000_000)

    func reading(_ id: String, remaining: Double, age: TimeInterval = 0, expired: Bool = false, blocked: Bool = false) -> ProviderUsage {
        ProviderUsage(id: id, name: id, installed: true, authenticated: true,
            windows: [UsageWindow(label: "Weekly", remainingPercent: remaining,
                                  resetsAt: now.addingTimeInterval(expired ? -1 : 3600))],
            updatedAt: now.addingTimeInterval(-age), condition: .ready, limitReached: blocked)
    }

    func testLowestNamesItsSourceAndExcludesStaleAndExpiredReadings() {
        let state = UsageOverview(providers: [reading("stale", remaining: 1, age: 601),
            reading("expired", remaining: 0, expired: true), reading("codex", remaining: 45),
            reading("claude", remaining: 23)], now: now)
        XCTAssertEqual(state.lowest?.provider.id, "claude")
        XCTAssertEqual(state.lowest?.window.label, "Weekly")
        XCTAssertEqual(state.currentCount, 2)
        XCTAssertEqual(state.statusText, "2 of 4 tools current")
    }

    func testExplicitBlockOverridesHealthyPercentButNotWhenStale() {
        let state = UsageOverview(providers: [reading("codex", remaining: 80, blocked: true)], now: now)
        XCTAssertEqual(state.blockedProvider?.id, "codex")
        XCTAssertEqual(state.statusText, "codex · limit reached")
        let stale = UsageOverview(providers: [reading("codex", remaining: 80, age: 601, blocked: true)], now: now)
        XCTAssertNil(stale.blockedProvider)
        XCTAssertEqual(stale.statusText, "No current readings")
    }

    func testUnknownAuthenticationDoesNotClaimSignedIn() {
        let reading = ProviderUsage(id: "codex", name: "Codex", installed: true, condition: .error)
        XCTAssertEqual(reading.connectionStatus, "Connection failed · sign-in status unknown")
    }

    func testOldCacheWithoutBlockedFieldStillDecodes() throws {
        let original = reading("codex", remaining: 80)
        let data = try JSONEncoder().encode(original)
        var object = try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
        object.removeValue(forKey: "limitReached")
        let decoded = try JSONDecoder().decode(ProviderUsage.self, from: JSONSerialization.data(withJSONObject: object))
        XCTAssertNil(decoded.limitReached)
        XCTAssertEqual(decoded.windows, original.windows)
    }
}
