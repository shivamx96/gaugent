import Foundation
import XCTest
@testable import GaugentCore

/// Drives the providers against fake `codex` and `claude` executables that refuse to start inference.
final class ProviderProcessTests: XCTestCase {
    private var directory: URL!

    override func setUpWithError() throws {
        directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString, isDirectory: true)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: directory)
    }

    private func install(_ name: String, script: String) throws -> String {
        let url = directory.appendingPathComponent(name)
        try ("#!/usr/bin/env python3\n" + script).write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: url.path)
        return url.path
    }

    private let fakeCodex = """
    import json, os, sys
    for line in sys.stdin:
        q = json.loads(line)
        method = q['method']
        if method == 'initialized':
            continue
        if method == 'initialize':
            result = {}
        elif method == 'account/read':
            account = os.environ.get('TEST_ACCOUNT', 'alice')
            result = {'account': None if account == 'none' else {
                'type': os.environ.get('TEST_AUTH_TYPE', 'chatgpt'), 'email': account, 'planType': 'pro'}}
        elif method == 'account/rateLimits/read':
            if os.environ.get('TEST_RATE_ERROR'):
                print(json.dumps({'id': q['id'], 'error': {'message': 'private provider error'}}), flush=True)
                continue
            result = {'rateLimits': {'primary': {'usedPercent': 23, 'windowDurationMins': 300, 'resetsAt': 2000}}}
        else:
            sys.exit('Unexpected request (must never start inference): ' + method)
        print(json.dumps({'method': 'notice', 'params': {}}), flush=True)
        print(json.dumps({'id': q['id'], 'result': result}), flush=True)
    """

    private let fakeClaude = """
    import json, os, sys
    if sys.argv[1:3] == ['auth', 'status']:
        print(json.dumps({'loggedIn': os.environ.get('TEST_LOGGED_OUT') is None, 'authMethod': os.environ.get('TEST_AUTH_METHOD', 'claude.ai'),
                          'email': os.environ.get('TEST_ACCOUNT', 'alice'), 'orgId': 'org', 'subscriptionType': 'pro'}))
        sys.exit()
    assert '--safe-mode' in sys.argv and '--no-session-persistence' in sys.argv
    assert sys.argv[sys.argv.index('--tools') + 1] == ''
    assert '--strict-mcp-config' in sys.argv
    for line in sys.stdin:
        q = json.loads(line)
        assert q['type'] == 'control_request', 'Never send a user prompt'
        subtype = q['request']['subtype']
        if subtype == 'initialize':
            result = {'commands': [{'name': 'x' * 30000}]}
        elif subtype == 'get_usage':
            assert q['request']['skip_behaviors'] is True
            if os.environ.get('TEST_RATE_ERROR'):
                print(json.dumps({'type': 'control_response', 'response': {'subtype': 'error', 'request_id': q['request_id'], 'error': 'private error'}}), flush=True)
                continue
            if os.environ.get('TEST_NULL_RATES'):
                result = {'rate_limits_available': True, 'rate_limits': None}
            else:
                result = {'rate_limits_available': True, 'rate_limits': {'limits': [
                    {'kind': 'weekly_all', 'percent': 41, 'resets_at': '2030-01-01T00:00:00Z'},
                    {'kind': 'weekly_scoped', 'percent': 64, 'resets_at': '2030-01-01T00:00:00Z', 'scope': {'model': {'display_name': 'Fable'}}}]}}
        else:
            raise AssertionError(subtype)
        print(json.dumps({'type': 'control_response', 'response': {'subtype': 'success', 'request_id': q['request_id'], 'response': result}}), flush=True)
    """

    private func withEnvironment(_ values: [String: String], _ body: () -> Void) {
        for (key, value) in values { setenv(key, value, 1) }
        defer { for key in values.keys { unsetenv(key) } }
        body()
    }

    func testCodexReadsAccountRetainsOnSameAccountOnlyAndReportsSignOut() throws {
        let path = try install("codex", script: fakeCodex)
        let provider = CodexProvider(preferredPath: path, home: directory)

        let first = provider.read(previous: nil)
        XCTAssertEqual(first.condition, .ready)
        XCTAssertEqual(first.plan, "pro")
        XCTAssertEqual(first.windows.map(\.remainingPercent), [77])
        XCTAssertEqual(first.windows.first?.label, "5-hour")
        XCTAssertFalse(try JSONEncoder().encode(first).contains("alice".data(using: .utf8)!.first!) && String(decoding: try JSONEncoder().encode(first), as: UTF8.self).contains("alice"))

        withEnvironment(["TEST_RATE_ERROR": "1"]) {
            let stale = provider.read(previous: first)
            XCTAssertEqual(stale.condition, .error)
            XCTAssertEqual(stale.windows, first.windows)
            XCTAssertFalse(stale.message.contains("private"))
        }
        withEnvironment(["TEST_RATE_ERROR": "1", "TEST_ACCOUNT": "bob"]) {
            XCTAssertEqual(provider.read(previous: first).windows, [])
        }
        withEnvironment(["TEST_ACCOUNT": "none"]) {
            let signedOut = provider.read(previous: first)
            XCTAssertFalse(signedOut.authenticated)
            XCTAssertEqual(signedOut.condition, .signedOut)
            XCTAssertEqual(signedOut.windows, [])
        }
        withEnvironment(["TEST_AUTH_TYPE": "apiKey"]) {
            XCTAssertEqual(provider.read(previous: first).condition, .unsupported)
        }
    }

    func testClaudeControlProtocolDualWeeklyLimitsNullRatesAndAccountChange() throws {
        let path = try install("claude", script: fakeClaude)
        let provider = ClaudeProvider(preferredPath: path, home: directory, configDirectory: directory)

        let first = provider.read(previous: nil)
        XCTAssertEqual(first.condition, .ready, first.message)
        XCTAssertEqual(first.plan, "pro")
        XCTAssertEqual(first.windows.map(\.label), ["Weekly · All models", "Weekly · Fable only"])
        XCTAssertEqual(first.windows.map(\.remainingPercent), [59, 36])
        XCTAssertFalse(String(decoding: try JSONEncoder().encode(first), as: UTF8.self).contains("alice"))

        withEnvironment(["TEST_RATE_ERROR": "1"]) {
            let retained = provider.read(previous: first)
            XCTAssertEqual(retained.condition, .error)
            XCTAssertEqual(retained.windows, first.windows)
        }
        withEnvironment(["TEST_NULL_RATES": "1"]) {
            let declined = provider.read(previous: first)
            XCTAssertEqual(declined.condition, .error)
            XCTAssertEqual(declined.windows, first.windows)
            XCTAssertTrue(declined.message.contains("retried"))
        }
        withEnvironment(["TEST_RATE_ERROR": "1", "TEST_ACCOUNT": "bob"]) {
            XCTAssertEqual(provider.read(previous: first).windows, [])
        }
        withEnvironment(["TEST_LOGGED_OUT": "1"]) {
            let signedOut = provider.read(previous: first)
            XCTAssertFalse(signedOut.authenticated)
            XCTAssertEqual(signedOut.condition, .signedOut)
        }
        withEnvironment(["TEST_AUTH_METHOD": "api_key"]) {
            XCTAssertEqual(provider.read(previous: first).condition, .unsupported)
        }
    }

    func testClaudeFallsBackToTheCLIsOwnSnapshotForTheSameAccountOnly() throws {
        let path = try install("claude", script: fakeClaude)
        let provider = ClaudeProvider(preferredPath: path, home: directory, configDirectory: directory)
        let configURL = directory.appendingPathComponent(".claude.json")

        func writeConfig(email: String, cachedAccount: String = "acc") throws {
            let object: [String: Any] = [
                "oauthAccount": ["emailAddress": email, "organizationUuid": "org", "accountUuid": "acc"],
                "cachedUsageUtilization": [
                    "fetchedAtMs": 1_700_000_000_000, "accountUuid": cachedAccount,
                    "utilization": ["limits": [["kind": "weekly_all", "percent": 42, "resets_at": "2030-01-01T00:00:00Z"]],
                                    "extra_usage": ["is_enabled": false]]
                ]
            ]
            try JSONSerialization.data(withJSONObject: object).write(to: configURL)
        }

        try writeConfig(email: "alice")
        withEnvironment(["TEST_NULL_RATES": "1"]) {
            let reading = provider.read(previous: nil)
            XCTAssertEqual(reading.condition, .ready)
            XCTAssertEqual(reading.windows.map(\.label), ["Weekly · All models"])
            XCTAssertEqual(reading.windows.map(\.remainingPercent), [58])
            XCTAssertEqual(reading.updatedAt, Date(timeIntervalSince1970: 1_700_000_000))
            XCTAssertTrue(reading.message.contains("last fetched"))
            XCTAssertTrue(reading.isStale(), "an old snapshot is shown but never trusted for warnings")
        }

        let live = provider.read(previous: nil)
        XCTAssertEqual(live.condition, .ready)
        withEnvironment(["TEST_NULL_RATES": "1"]) {
            let kept = provider.read(previous: live)
            XCTAssertEqual(kept.windows, live.windows, "a fresher previous reading beats an older snapshot")
            XCTAssertEqual(kept.condition, .error)
        }

        try writeConfig(email: "bob")
        withEnvironment(["TEST_NULL_RATES": "1"]) {
            XCTAssertEqual(provider.read(previous: nil).windows, [])
        }
        try writeConfig(email: "alice", cachedAccount: "someone-else")
        withEnvironment(["TEST_NULL_RATES": "1"]) {
            XCTAssertEqual(provider.read(previous: nil).windows, [])
        }
    }

    func testMissingExecutablesStartNothing() {
        let nothing: ExecutableResolver = { _, _, _ in nil }
        let codex = CodexProvider(home: directory, resolver: nothing)
        let claude = ClaudeProvider(home: directory, resolver: nothing)
        XCTAssertEqual(codex.read(previous: nil).condition, .notInstalled)
        XCTAssertEqual(claude.read(previous: nil).condition, .notInstalled)
    }

    func testTimeoutDoesNotLeaveChildRunning() throws {
        let path = try install("sleeper", script: "import time\ntime.sleep(60)\n")
        let client = LineProcessClient(executable: path, arguments: [], currentDirectory: directory, timeout: 0.3)
        try client.start()
        XCTAssertThrowsError(try client.receive { _ in true }) { error in
            XCTAssertEqual(error as? LineProcessError, .timedOut)
        }
        client.terminate()
        XCTAssertFalse(client.isRunning)
    }

    func testClientSkipsNoiseAndDetectsDisconnect() throws {
        let path = try install("echoer", script: """
        import json, sys
        print('not json', flush=True)
        print(json.dumps({'method': 'notice'}), flush=True)
        for line in sys.stdin:
            q = json.loads(line)
            print(json.dumps({'id': q['id'], 'result': {'ok': True}}), flush=True)
            break
        """)
        let client = LineProcessClient(executable: path, arguments: [], currentDirectory: directory, timeout: 5)
        try client.start()
        let rpc = JSONRPCSession(client: client)
        XCTAssertEqual(try rpc.request("ping")["ok"] as? Bool, true)
        XCTAssertThrowsError(try rpc.request("again")) { error in
            XCTAssertEqual(error as? LineProcessError, .disconnected)
        }
    }

    func testCollectorKeepsProviderOrderAndHonoursEnabledSet() async throws {
        let codex = try install("codex", script: fakeCodex)
        let claude = try install("claude", script: fakeClaude)
        let collector = UsageCollector(providers: [
            ClaudeProvider(preferredPath: claude, home: directory, configDirectory: directory),
            CodexProvider(preferredPath: codex, home: directory)
        ])
        let all = await collector.collect(previous: nil)
        XCTAssertEqual(all.providers.map(\.id), ["claude", "codex"])
        let only = await collector.collect(previous: nil, enabled: ["codex"])
        XCTAssertEqual(only.providers.map(\.id), ["codex"])
    }

    func testCacheRoundTripsAndRejectsOtherVersions() throws {
        let url = directory.appendingPathComponent("cache/usage.json")
        let snapshot = UsageSnapshot(checkedAt: Date(timeIntervalSince1970: 1000), providers: [
            ProviderUsage(id: "codex", name: "Codex", installed: true, authenticated: true, plan: "pro",
                          windows: [UsageWindow(label: "7-day", remainingPercent: 66, resetsAt: Date(timeIntervalSince1970: 2000))],
                          notes: ["n"], updatedAt: Date(timeIntervalSince1970: 1000), condition: .ready, accountKey: "k")
        ])
        UsageCache.save(snapshot, to: url)
        XCTAssertEqual(UsageCache.load(from: url), snapshot)
        let permissions = try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as? Int
        XCTAssertEqual(permissions, 0o600)

        var old = snapshot
        old.version = 0
        UsageCache.save(old, to: url)
        XCTAssertNil(UsageCache.load(from: url))
        try "[]".write(to: url, atomically: true, encoding: .utf8)
        XCTAssertNil(UsageCache.load(from: url))
    }
}
