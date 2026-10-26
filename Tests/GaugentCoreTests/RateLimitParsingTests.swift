import Foundation
import XCTest
@testable import GaugentCore

final class RateLimitParsingTests: XCTestCase {
    func testOutOfRangeNumbersDoNotTrapOrProduceMisleadingLabels() {
        for value in [1e100, Double(Int.max), Double.infinity, Double.nan, -1] {
            let reading = CodexRateLimits.parse(["rateLimitResetCredits": ["availableCount": value]])
            XCTAssertTrue(reading.notes.isEmpty)
            XCTAssertEqual(CodexRateLimits.durationLabel(minutes: value, fallback: "Primary"), "Primary")
            XCTAssertEqual(ClaudeRateLimits.notes(["extra_usage": ["is_enabled": true,
                "used_credits": value, "monthly_limit": value]]), ["Extra usage on"])
            XCTAssertNil(resetDate(value))
        }
        XCTAssertTrue(CodexRateLimits.parse(["rateLimitResetCredits": ["availableCount": 1.5]]).notes.isEmpty)
        XCTAssertEqual(CodexRateLimits.durationLabel(minutes: 1.5, fallback: "Primary"), "1.5-minute")
        XCTAssertEqual(CodexRateLimits.parse(["rateLimitResetCredits": ["availableCount": 1]]).notes,
                       ["1 full reset available"])
        XCTAssertEqual(resetDate(Date.distantFuture.timeIntervalSince1970), Date.distantFuture)
    }

    func testCodexWindowsKeepZeroMissingDurationAndMultipleBuckets() {
        let reading = CodexRateLimits.parse(["rateLimitsByLimitId": [
            "codex": ["primary": ["usedPercent": 100, "windowDurationMins": 10080, "resetsAt": 10]],
            "other": ["limitName": "Other model", "primary": ["usedPercent": 0], "secondary": ["usedPercent": NSNull()]]
        ]])
        XCTAssertEqual(reading.windows.map(\.remainingPercent), [0, 100])
        XCTAssertEqual(reading.windows[0].label, "codex · 7-day")
        XCTAssertEqual(reading.windows[0].resetsAt, Date(timeIntervalSince1970: 10)) // expired is not replenished
        XCTAssertEqual(reading.windows[1].label, "Other model · Primary")
        XCTAssertNil(reading.windows[1].resetsAt)
        XCTAssertFalse(reading.limitReached)
        XCTAssertEqual(CodexRateLimits.parse(["rateLimits": ["primary": NSNull()]]).windows, [])
    }

    func testCodexSingleBucketSpendLimitCreditsAndReachedFlags() {
        let reading = CodexRateLimits.parse([
            "ordinaryUsageAllowed": true,
            "rateLimits": [
                "primary": ["usedPercent": 32, "windowDurationMins": 300, "resetsAt": 2000],
                "secondary": ["usedPercent": 10, "windowDurationMins": 10080],
                "individualLimit": ["remainingPercent": 25.5, "resetsAt": 3000],
                "credits": ["hasCredits": true, "unlimited": false, "balance": "12.50"],
                "rateLimitReachedType": "primary"
            ],
            "rateLimitResetCredits": ["availableCount": 3]
        ])
        XCTAssertEqual(reading.windows.map(\.label), ["5-hour", "7-day", "Spend limit"])
        XCTAssertEqual(reading.windows.map(\.remainingPercent), [68, 90, 25.5])
        XCTAssertEqual(reading.notes, ["Credit balance 12.50", "3 full resets available"])
        XCTAssertTrue(reading.limitReached)
        XCTAssertTrue(CodexRateLimits.parse(["ordinaryUsageAllowed": false]).limitReached)
    }

    func testDurationLabels() {
        XCTAssertEqual(CodexRateLimits.durationLabel(minutes: 300, fallback: "Primary"), "5-hour")
        XCTAssertEqual(CodexRateLimits.durationLabel(minutes: 10080, fallback: "Primary"), "7-day")
        XCTAssertEqual(CodexRateLimits.durationLabel(minutes: 90, fallback: "Primary"), "90-minute")
        XCTAssertEqual(CodexRateLimits.durationLabel(minutes: nil, fallback: "Secondary"), "Secondary")
        XCTAssertEqual(CodexRateLimits.durationLabel(minutes: 0, fallback: "Secondary"), "Secondary")
    }

    func testInvalidNumbersAreNotAllowances() {
        for value in [NSNull(), true, "20", Double.nan, Double.infinity, -1] as [Any] {
            XCTAssertNil(usageWindow(label: "test", usedPercent: value, resetsAt: nil), "\(value)")
        }
        XCTAssertEqual(usageWindow(label: "spend", usedPercent: 125, resetsAt: nil)?.remainingPercent, 0)
        XCTAssertNil(resetDate("not-a-date"))
        XCTAssertNil(resetDate(0))
        XCTAssertEqual(resetDate("2030-01-01T00:00:00+00:00"), Date(timeIntervalSince1970: 1_893_456_000))
        XCTAssertEqual(resetDate("2030-01-01T00:00:00.000Z"), Date(timeIntervalSince1970: 1_893_456_000))
    }

    func testClaudeNamedLimitsWinAndLegacyFieldsFillGaps() {
        let windows = ClaudeRateLimits.windows([
            "five_hour": ["utilization": 0, "resets_at": NSNull()],
            "seven_day": ["utilization": 100, "resets_at": "2030-01-01T00:00:00Z"],
            "model_scoped": [["display_name": "Fable", "utilization": 50, "resets_at": NSNull()]],
            "limits": [
                ["kind": "weekly_scoped", "percent": 64, "resets_at": "2030-01-01T00:00:00Z", "scope": ["model": ["display_name": "Fable"]]],
                ["kind": "weekly_all", "percent": 41, "resets_at": "2030-01-01T00:00:00Z"],
                ["kind": "unknown", "percent": 1]
            ]
        ])
        XCTAssertEqual(windows.map(\.label), ["Weekly · Fable only", "Weekly · All models", "Session · 5-hour"])
        XCTAssertEqual(windows.map(\.remainingPercent), [36, 59, 100])
        XCTAssertEqual(ClaudeRateLimits.windows([:]), [])
    }

    func testClaudeLegacyOpusSonnetAndExtraUsageNotes() {
        let windows = ClaudeRateLimits.windows([
            "seven_day_opus": ["utilization": 20, "resets_at": 1000],
            "seven_day_sonnet": ["utilization": 5]
        ])
        XCTAssertEqual(windows.map(\.label), ["Weekly · Opus only", "Weekly · Sonnet only"])
        XCTAssertEqual(ClaudeRateLimits.notes(["extra_usage": ["is_enabled": true, "monthly_limit": 50, "used_credits": 12.5]]),
                       ["Extra usage on · $12.50 of $50 this month"])
        XCTAssertEqual(ClaudeRateLimits.notes(["extra_usage": ["is_enabled": false]]), [])
    }

    func testMaxTierRequiresMatchingAccountAndKnownTier() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let auth = ClaudeAuthentication(loggedIn: true, authMethod: "claude.ai", email: "alice", orgId: "org", subscriptionType: "max", accountKey: nil)

        func write(_ profile: [String: Any]) throws {
            let data = try JSONSerialization.data(withJSONObject: ["oauthAccount": profile])
            try data.write(to: directory.appendingPathComponent(".claude.json"))
        }

        var profile: [String: Any] = ["emailAddress": "alice", "organizationUuid": "org", "organizationRateLimitTier": "default_claude_max_5x"]
        try write(profile)
        XCTAssertEqual(ClaudePlan.resolve(auth: auth, configDirectory: directory), "max_5x")
        // A JSON null user tier must fall back to the organization's known tier.
        profile["userRateLimitTier"] = NSNull()
        try write(profile)
        XCTAssertEqual(ClaudePlan.resolve(auth: auth, configDirectory: directory), "max_5x")
        // Real CLI behavior: subscriptionType can be "pro" for a Max 5× account.
        var proAuth = auth
        proAuth.subscriptionType = "pro"
        XCTAssertEqual(ClaudePlan.resolve(auth: proAuth, configDirectory: directory), "max_5x")
        var mismatchedPro = proAuth
        mismatchedPro.email = "someone-else"
        XCTAssertEqual(ClaudePlan.resolve(auth: mismatchedPro, configDirectory: directory), "pro")
        var teamAuth = auth
        teamAuth.subscriptionType = "team"
        XCTAssertEqual(ClaudePlan.resolve(auth: teamAuth, configDirectory: directory), "team")
        var signedOut = proAuth
        signedOut.loggedIn = false
        XCTAssertEqual(ClaudePlan.resolve(auth: signedOut, configDirectory: directory), "pro")
        profile["userRateLimitTier"] = "default_claude_max_20x"
        try write(profile)
        XCTAssertEqual(ClaudePlan.resolve(auth: auth, configDirectory: directory), "max_20x")
        XCTAssertEqual(ClaudePlan.resolve(auth: proAuth, configDirectory: directory), "max_20x")

        var other = auth
        other.email = "bob"
        XCTAssertEqual(ClaudePlan.resolve(auth: other, configDirectory: directory), "max")
        other = auth
        other.orgId = "different"
        XCTAssertEqual(ClaudePlan.resolve(auth: other, configDirectory: directory), "max")

        profile["userRateLimitTier"] = "unknown-tier"
        try write(profile)
        XCTAssertEqual(ClaudePlan.resolve(auth: proAuth, configDirectory: directory), "pro")
        XCTAssertEqual(ClaudePlan.resolve(auth: auth, configDirectory: directory), "max")
        try FileManager.default.removeItem(at: directory.appendingPathComponent(".claude.json"))
        XCTAssertEqual(ClaudePlan.resolve(auth: auth, configDirectory: directory), "max")
        var pro = auth
        pro.subscriptionType = "pro"
        XCTAssertEqual(ClaudePlan.resolve(auth: pro, configDirectory: directory), "pro")
    }

    func testCodexProPriceLabelsAreProviderSpecific() {
        for (plan, label) in [("prolite", "Pro $100"), ("pro", "Pro $200"), ("promax", "Pro $500")] {
            let usage = ProviderUsage(id: "codex", name: "Codex", authenticated: true, plan: plan, condition: .ready)
            XCTAssertEqual(usage.planLabel, label)
        }
        let claude = ProviderUsage(id: "claude", name: "Claude Code", authenticated: true, plan: "pro", condition: .ready)
        XCTAssertEqual(claude.planLabel, "Pro")
    }

    func testPlanLabelsAndStaleness() {
        var usage = ProviderUsage(id: "x", name: "X", installed: true, authenticated: true, plan: "max_20x", condition: .ready)
        XCTAssertEqual(usage.planLabel, "Max 20×")
        usage.plan = "custom_tier"
        XCTAssertEqual(usage.planLabel, "custom tier")
        usage.plan = ""
        XCTAssertEqual(usage.planLabel, "Signed in")
        usage.authenticated = false
        XCTAssertEqual(usage.planLabel, "Not signed in")
        usage.condition = .error
        XCTAssertEqual(usage.planLabel, "Unavailable")

        let now = Date()
        var fresh = ProviderUsage(id: "x", name: "X", windows: [
            UsageWindow(label: "a", remainingPercent: 40, resetsAt: now.addingTimeInterval(60)),
            UsageWindow(label: "b", remainingPercent: 10, resetsAt: now.addingTimeInterval(-60))
        ], updatedAt: now, condition: .ready)
        XCTAssertFalse(fresh.isStale(at: now))
        XCTAssertEqual(fresh.lowestRemaining(at: now), 40, "an expired window is awaiting an update, not low")
        XCTAssertTrue(fresh.isStale(at: now.addingTimeInterval(601)))
        XCTAssertTrue(fresh.isStale(at: now.addingTimeInterval(-1)), "a reading from the future is not trusted")
        fresh.condition = .error
        XCTAssertTrue(fresh.isStale(at: now))
    }

    func testRetentionRequiresSameAccount() {
        let previous = ProviderUsage(id: "x", name: "X", windows: [UsageWindow(label: "a", remainingPercent: 50, resetsAt: nil)],
                                     notes: ["note"], updatedAt: Date(timeIntervalSince1970: 100), condition: .ready, accountKey: "k1")
        var same = ProviderUsage(id: "x", name: "X", authenticated: true, accountKey: "k1")
        same.retainReading(from: previous, message: "failed")
        XCTAssertEqual(same.windows, previous.windows)
        XCTAssertEqual(same.notes, ["note"])
        XCTAssertEqual(same.updatedAt, previous.updatedAt)
        XCTAssertEqual(same.condition, .error)

        var other = ProviderUsage(id: "x", name: "X", authenticated: true, accountKey: "k2")
        other.retainReading(from: previous, message: "failed")
        XCTAssertEqual(other.windows, [])
        var anonymous = ProviderUsage(id: "x", name: "X", authenticated: true, accountKey: nil)
        anonymous.retainReading(from: previous, message: "failed")
        XCTAssertEqual(anonymous.windows, [])
    }

    func testAccountIdentityIsHashedAndOrderIndependent() {
        let key = AccountIdentity.key(["email": "alice@example.com", "org": "o"])
        XCTAssertEqual(key, AccountIdentity.key(["org": "o", "email": "alice@example.com"]))
        XCTAssertEqual(key?.count, 64)
        XCTAssertFalse(key!.contains("alice"))
        XCTAssertNil(AccountIdentity.key(["email": nil, "org": ""]))
    }
}
