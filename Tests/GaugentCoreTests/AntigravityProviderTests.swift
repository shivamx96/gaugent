import Foundation
import XCTest
@testable import GaugentCore

final class AntigravityProviderTests: XCTestCase {
    private let quota: [String: Any] = ["groups": [
        ["name": "Gemini Models", "buckets": [
            ["id": "gemini-weekly", "window": "weekly", "remaining_fraction": 0.42, "reset_time": "2099-11-28T06:58:12Z"],
            ["id": "gemini-5h", "window": "5h", "remaining_fraction": 0.98, "reset_time": "2099-11-21T11:58:12Z"]
        ]],
        ["name": "Claude and GPT models", "buckets": [
            ["id": "3p-weekly", "window": "weekly", "remaining_fraction": 1.0]
        ]]
    ]]

    private func response(_ quota: [String: Any]) throws -> ProcessResult {
        let payload: [String: Any] = ["status": "SUCCESS", "conversation_id": "", "num_turns": 0,
            "usage": ["total_tokens": 0], "command": ["name": "usage", "data": quota]]
        return ProcessResult(standardOutput: String(decoding: try JSONSerialization.data(withJSONObject: payload), as: UTF8.self),
                             standardError: "", terminationStatus: 0)
    }

    private func provider(_ runner: AntigravityRunner) -> AntigravityProvider {
        AntigravityProvider(runner: runner, home: URL(fileURLWithPath: "/tmp"), resolver: { _, _, _ in "/fake/agy" })
    }

    func testReadsStructuredGroupsWithoutConversationsOrCredentials() throws {
        let runner = AntigravityRunner(result: try response(quota))
        let reading = provider(runner).read(previous: nil)
        XCTAssertEqual(reading.condition, .ready)
        XCTAssertTrue(reading.authenticated)
        XCTAssertNil(reading.accountKey)
        XCTAssertEqual(reading.planLabel, "Signed in", "Do not infer a subscription tier from model names")
        XCTAssertEqual(reading.windows.map(\.remainingPercent), [42, 98, 100])
        XCTAssertEqual(reading.windows.map(\.durationMinutes), [10080, 300, 10080])
        XCTAssertNotNil(reading.windows[0].resetsAt)
        XCTAssertNil(reading.windows[2].resetsAt)
        XCTAssertEqual(runner.calls, [["--help"], ["changelog"], AntigravityProvider.usageArguments])
        XCTAssertTrue(AntigravityProvider.usageArguments.contains(#"{"disableSlashCommands":false}"#))
        XCTAssertFalse(provider(runner).allowsPersistedReadings)
    }

    func testUnsupportedOrUnknownVersionsNeverReceivePrintInput() throws {
        for version in ["1.1.10:", "1.1.11:", "garbage", "9999999999999999999999.0.0:"] {
            let runner = AntigravityRunner(result: try response(quota), changelog: version)
            let reading = provider(runner).read(previous: nil)
            XCTAssertEqual(reading.condition, .error)
            XCTAssertEqual(runner.calls, [["--help"], ["changelog"]])
        }
        for version in ["1.1.12:", "1.5.13:\nNotes", "2.0.0:"] {
            XCTAssertTrue(AntigravityProvider.supportsUsageCommand(version))
        }
        let runner = AntigravityRunner(result: try response(quota), help: "old help")
        XCTAssertEqual(provider(runner).read(previous: nil).condition, .error)
        XCTAssertEqual(runner.calls, [["--help"]])
    }

    func testMissingCLIStartsNothing() throws {
        let runner = AntigravityRunner(result: try response(quota))
        let missing = AntigravityProvider(runner: runner, resolver: { _, _, _ in nil }).read(previous: nil)
        XCTAssertEqual(missing.condition, .notInstalled)
        XCTAssertTrue(runner.calls.isEmpty)
    }

    func testFailedRefreshDoesNotRetainAnUnidentifiedAccountsReadings() throws {
        let good = provider(AntigravityRunner(result: try response(quota))).read(previous: nil)
        let runner = AntigravityRunner(result: ProcessResult(standardOutput: "", standardError: "private account error", terminationStatus: -1))
        let failed = provider(runner).read(previous: good)
        XCTAssertEqual(failed.condition, .error)
        XCTAssertEqual(failed.failureStreak, 1)
        XCTAssertTrue(failed.windows.isEmpty)
        XCTAssertNil(failed.updatedAt)
        XCTAssertFalse(failed.message.contains("private account error"))
    }

    func testSignOutAndAPIKeyHaveActionableStatesWithoutLeakingOutput() {
        for (error, condition) in [("Error: authentication required. private@example.com", ProviderCondition.signedOut),
                                    ("not authenticated: no stored credentials found", .signedOut),
                                    ("GEMINI_API_KEY has no account quota", .unsupported)] {
            let runner = AntigravityRunner(result: ProcessResult(standardOutput: "", standardError: error, terminationStatus: 2))
            let reading = provider(runner).read(previous: nil)
            XCTAssertEqual(reading.condition, condition)
            XCTAssertFalse(reading.authenticated)
            XCTAssertFalse(reading.message.contains("private@example.com"))
        }
    }

    func testRejectsMalformedResponsesAndModelTurns() throws {
        let original = try XCTUnwrap(try JSONSerialization.jsonObject(with: Data(response(quota).standardOutput.utf8)) as? [String: Any])
        for field in ["conversation_id", "num_turns", "usage", "command", "status"] {
            var changed = original
            changed[field] = ["conversation_id": "unexpected", "num_turns": 1, "usage": ["total_tokens": 1],
                              "command": ["name": "other"], "status": "ERROR"][field]
            let json = String(decoding: try JSONSerialization.data(withJSONObject: changed), as: UTF8.self)
            let runner = AntigravityRunner(result: ProcessResult(standardOutput: json, standardError: "", terminationStatus: 0))
            XCTAssertEqual(provider(runner).read(previous: nil).condition, .error, field)
        }
        let runner = AntigravityRunner(result: ProcessResult(standardOutput: "not JSON", standardError: "", terminationStatus: 0))
        XCTAssertEqual(provider(runner).read(previous: nil).condition, .error)
    }

    func testExhaustedGroupDoesNotBlockAnotherGroup() throws {
        var groups = try XCTUnwrap(quota["groups"] as? [[String: Any]])
        var buckets = try XCTUnwrap(groups[0]["buckets"] as? [[String: Any]])
        buckets[0]["remaining_fraction"] = 0
        groups[0]["buckets"] = buckets
        let reading = provider(AntigravityRunner(result: try response(["groups": groups]))).read(previous: nil)
        XCTAssertEqual(reading.usableWindows().count, 1)
        XCTAssertTrue(reading.usableWindows()[0].label.contains("Claude and GPT"))
        XCTAssertEqual(reading.windows[0].scopeID, reading.windows[1].scopeID)
        XCTAssertNotEqual(reading.windows[0].scopeID, reading.windows[2].scopeID)
    }

    func testUnknownOrDisabledConstraintNeverMakesAGroupLookUsable() throws {
        for invalid: Any in [true, -0.1, 1.1, "0.5", NSNull()] {
            var groups = try XCTUnwrap(quota["groups"] as? [[String: Any]])
            var buckets = try XCTUnwrap(groups[0]["buckets"] as? [[String: Any]])
            buckets[0]["remaining_fraction"] = invalid
            groups[0]["buckets"] = buckets
            let reading = try XCTUnwrap(AntigravityQuotas.parse(["groups": groups]))
            XCTAssertEqual(reading.windows.count, 1)
            XCTAssertEqual(reading.blockedScopes.count, 1)
            XCTAssertFalse(reading.notes.isEmpty)
        }
        for constraint: [String: Any] in [["disabled": true], ["remaining_amount": 30],
                                          ["remaining_fraction": 0.5, "reset_time": "not a date"]] {
            let bucket = constraint.merging(["id": "weekly", "window": "weekly"]) { old, _ in old }
            let reading = try XCTUnwrap(AntigravityQuotas.parse(["groups": [["name": "Gemini", "buckets": [bucket]]]]))
            XCTAssertTrue(reading.windows.isEmpty)
            XCTAssertFalse(reading.notes.isEmpty)
        }
    }

    func testMalformedGroupsAndDuplicateBucketsAreRejected() {
        XCTAssertNil(AntigravityQuotas.parse([:]))
        XCTAssertNil(AntigravityQuotas.parse(["groups": [["name": "Gemini"]]]))
        let bucket: [String: Any] = ["id": "weekly", "remaining_fraction": 0.5]
        XCTAssertNil(AntigravityQuotas.parse(["groups": [["name": "Gemini", "buckets": [bucket, bucket]]]]))
        XCTAssertEqual(AntigravityQuotas.parse(["groups": []])?.windows, [])
    }

    func testRepeatedGroupNamesStillHaveUniqueWindowLabels() throws {
        let groups = ["one", "two"].map { id in
            ["name": "Gemini", "buckets": [["id": id, "window": "weekly", "remaining_fraction": 0.5]]] as [String: Any]
        }
        let reading = try XCTUnwrap(AntigravityQuotas.parse(["groups": groups]))
        XCTAssertEqual(Set(reading.windows.map(\.id)).count, 2)
    }

    func testCacheExcludesAntigravityEvenIfAnOlderBuildSavedIt() throws {
        let reading = provider(AntigravityRunner(result: try response(quota))).read(previous: nil)
        let codex = ProviderUsage(id: "codex", name: "Codex", accountKey: "verified")
        let snapshot = UsageSnapshot(checkedAt: Date(), providers: [reading, codex])
        XCTAssertEqual(UsageCollector.standard.cacheableSnapshot(snapshot).providers, [codex])
    }

    func testLiveAntigravityReadWhenExplicitlyRequested() throws {
        guard ProcessInfo.processInfo.environment["GAUGENT_LIVE_ANTIGRAVITY"] == "1" else {
            throw XCTSkip("Opt-in check against the locally signed-in CLI")
        }
        let reading = AntigravityProvider().read(previous: nil)
        XCTAssertEqual(reading.condition, .ready, reading.message)
        XCTAssertFalse(reading.windows.isEmpty)
        XCTAssertNil(reading.accountKey)
    }
}

private final class AntigravityRunner: ProcessRunning, @unchecked Sendable {
    private let lock = NSLock()
    private var recorded: [[String]] = []
    var calls: [[String]] { lock.lock(); defer { lock.unlock() }; return recorded }
    let result: ProcessResult
    let changelog: String
    let help: String

    init(result: ProcessResult, changelog: String = "1.5.13:\nRelease notes", help: String = "--settings --print-timeout changelog") {
        self.result = result
        self.changelog = changelog
        self.help = help
    }

    func run(executable: String, arguments: [String], currentDirectory: URL?) -> ProcessResult {
        lock.lock(); recorded.append(arguments); lock.unlock()
        if arguments == ["--help"] { return ProcessResult(standardOutput: "", standardError: help, terminationStatus: 0) }
        if arguments == ["changelog"] { return ProcessResult(standardOutput: changelog, standardError: "", terminationStatus: 0) }
        // Refuse every input except the reviewed read-only command.
        guard arguments == AntigravityProvider.usageArguments else {
            return ProcessResult(standardOutput: "", standardError: "Unexpected command", terminationStatus: -1)
        }
        return result
    }
}
