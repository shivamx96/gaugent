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

    func testExhaustedSharedWindowExcludesPositiveSiblingAndSelectsOtherProvider() {
        var claude = reading("claude", remaining: 0)
        claude.windows.append(UsageWindow(label: "5-hour", remainingPercent: 80, resetsAt: nil))
        let state = UsageOverview(providers: [claude, reading("codex", remaining: 45)], now: now)
        XCTAssertEqual(state.lowestUsable?.provider.id, "codex")
        XCTAssertEqual(state.lowestUsable?.window.remainingPercent, 45)
        XCTAssertEqual(state.blockedProvider?.id, "claude")
        XCTAssertNil(UsageOverview(providers: [claude], now: now).lowestUsable)
    }

    func testScopedExhaustionDoesNotExcludeAnotherModelButSharedExhaustionDoes() {
        var claude = reading("claude", remaining: 60)
        claude.windows += [
            UsageWindow(label: "Opus weekly", remainingPercent: 0, resetsAt: nil, scopeID: "opus"),
            UsageWindow(label: "Opus session", remainingPercent: 5, resetsAt: nil, scopeID: "opus"),
            UsageWindow(label: "Sonnet weekly", remainingPercent: 30, resetsAt: nil, scopeID: "sonnet")
        ]
        XCTAssertEqual(UsageOverview(providers: [claude], now: now).lowestUsable?.window.label, "Sonnet weekly")
        claude.windows[0] = UsageWindow(label: "Weekly", remainingPercent: 0, resetsAt: nil)
        XCTAssertNil(UsageOverview(providers: [claude], now: now).lowestUsable)
    }

    func testExpiredSharedConstraintIsUnknownUntilRefreshed() {
        var claude = reading("claude", remaining: 0, expired: true)
        claude.windows.append(UsageWindow(label: "5-hour", remainingPercent: 80, resetsAt: nil))
        let state = UsageOverview(providers: [claude], now: now)
        XCTAssertNil(state.lowestUsable)
        XCTAssertNil(state.blockedProvider)
    }

    func testSingleModelLimitDoesNotBlockUnscopedUsage() {
        var claude = reading("claude", remaining: 60)
        claude.windows.append(UsageWindow(label: "Opus weekly", remainingPercent: 0,
                                          resetsAt: nil, scopeID: "opus"))
        XCTAssertEqual(UsageOverview(providers: [claude], now: now).lowestUsable?.window.remainingPercent, 60)
    }

    func testExplicitBlockStaleReadingsAndEqualPercentages() {
        let state = UsageOverview(providers: [reading("blocked", remaining: 1, blocked: true),
            reading("stale", remaining: 2, age: 601), reading("claude", remaining: 20),
            reading("codex", remaining: 20)], now: now)
        XCTAssertEqual(state.lowestUsable?.provider.id, "claude")
    }

    func testCodexBucketsRespectIndependentBlocksAndGlobalBlock() {
        let payload: [String: Any] = ["rateLimitsByLimitId": [
            "codex": ["primary": ["usedPercent": 10], "secondary": ["usedPercent": 20],
                      "rateLimitReachedType": "primary"],
            "other": ["primary": ["usedPercent": 70], "secondary": ["usedPercent": 50]]
        ]]
        let parsed = CodexRateLimits.parse(payload)
        var codex = reading("codex", remaining: 100)
        codex.windows = parsed.windows
        codex.limitReached = parsed.limitReached
        codex.blockedScopes = parsed.blockedScopes
        XCTAssertEqual(UsageOverview(providers: [codex], now: now).lowestUsable?.window.scopeID, "other")
        XCTAssertEqual(UsageOverview(providers: [codex], now: now).lowestUsable?.window.remainingPercent, 30)
        codex.limitReached = true
        XCTAssertNil(UsageOverview(providers: [codex], now: now).lowestUsable)
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

    func testLegacyWindowsDecodeWithoutScopeMetadata() throws {
        let data = Data(#"{"label":"Weekly","remainingPercent":30,"resetsAt":null}"#.utf8)
        let window = try JSONDecoder().decode(UsageWindow.self, from: data)
        XCTAssertNil(window.scopeID)
        XCTAssertNil(window.durationMinutes)
        XCTAssertEqual(window.remainingPercent, 30)
    }

    func testNonFiniteResetIsUnknownRatherThanExpired() {
        for seconds in [Double.nan, Double.infinity, -Double.infinity] {
            let window = UsageWindow(label: "Weekly", remainingPercent: 30,
                                     resetsAt: Date(timeIntervalSince1970: seconds))
            XCTAssertFalse(window.isExpired(at: now), "Invalid reset: \(seconds)")
        }
    }
}
