import XCTest
import GaugentCore
@testable import Gaugent

final class AppModelTests: XCTestCase {
    @MainActor
    func testNewProviderIsEnabledOnceWithoutReenablingDisabledTools() {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        defer { defaults.removePersistentDomain(forName: suite) }
        defaults.set(["codex"], forKey: "enabledProviderIDs")
        let first = AppModel(defaults: defaults, storageURL: nil, startAutomatically: false)
        XCTAssertEqual(first.enabledProviderIDs, ["codex", "antigravity"])
        defaults.set(["codex"], forKey: "enabledProviderIDs")
        let second = AppModel(defaults: defaults, storageURL: nil, startAutomatically: false)
        XCTAssertEqual(second.enabledProviderIDs, ["codex"])
        defaults.removeObject(forKey: "knownProviderIDs")
        defaults.set([String](), forKey: "enabledProviderIDs")
        let disabled = AppModel(defaults: defaults, storageURL: nil, startAutomatically: false)
        XCTAssertTrue(disabled.enabledProviderIDs.isEmpty)
    }

    @MainActor
    func testTransientReadingsAreLiveButNeverRestoredOrSaved() async throws {
        let suite = UUID().uuidString
        let defaults = UserDefaults(suiteName: suite)!
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { defaults.removePersistentDomain(forName: suite); try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("usage.json")
        let provider = TransientProvider()
        UsageCache.save(UsageSnapshot(checkedAt: Date(), providers: [provider.read(previous: nil)]), to: url)
        let model = AppModel(collector: UsageCollector(providers: [provider]), defaults: defaults,
                             storageURL: url, startAutomatically: false)
        XCTAssertEqual(model.visibleProviders, [])
        await model.refresh(reason: .user)
        XCTAssertEqual(model.visibleProviders.count, 1)
        XCTAssertEqual(UsageCache.load(from: url)?.providers, [])
    }

    @MainActor
    func testUnrepresentableCachedDatesHaveSafePresentation() {
        let model = AppModel(collector: UsageCollector(providers: []),
            defaults: UserDefaults(suiteName: UUID().uuidString)!, storageURL: nil, startAutomatically: false)
        for seconds in [1e100, -1e100, Double.infinity, Double.nan] {
            let date = Date(timeIntervalSince1970: seconds)
            XCTAssertEqual(model.resetText(UsageWindow(label: "Test", remainingPercent: 50, resetsAt: date)),
                           "Reset time unavailable")
            let reading = ProviderUsage(id: "test", name: "Test", updatedAt: date, condition: .error,
                                        attemptedAt: date, failureStreak: 1)
            XCTAssertEqual(model.ageText(reading), "Reading time unavailable")
            XCTAssertNil(model.nextAttemptText(reading))
        }
    }

    @MainActor
    func testUnavailableAndDisabledToolsHaveDifferentStates() async {
        let defaults = UserDefaults(suiteName: UUID().uuidString)!
        let model = AppModel(collector: UsageCollector(providers: [FailingProvider()]), defaults: defaults,
                             storageURL: nil, startAutomatically: false)
        await model.refresh(reason: .user)
        XCTAssertEqual(model.visibleProviders.count, 1)
        XCTAssertEqual(model.overview.statusText, "No current readings")
        model.setProvider("test", enabled: false)
        XCTAssertTrue(model.visibleProviders.isEmpty)
        XCTAssertEqual(model.headline, "No tools enabled")
    }

    @MainActor
    func testResetDuringRefreshCannotRestorePreviousReading() async throws {
        let folder = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: folder) }
        let url = folder.appendingPathComponent("usage.json")
        let previous = ProviderUsage(id: "test", name: "Test", installed: true, authenticated: true,
            windows: [UsageWindow(label: "Weekly", remainingPercent: 17, resetsAt: nil)],
            updatedAt: Date(), condition: .ready, accountKey: "same")
        UsageCache.save(UsageSnapshot(checkedAt: Date(), providers: [previous]), to: url)
        let model = AppModel(collector: UsageCollector(providers: [FailingProvider()]),
            defaults: UserDefaults(suiteName: UUID().uuidString)!, storageURL: url, startAutomatically: false)
        XCTAssertEqual(model.lowestRemaining, 17)
        let refresh = Task { await model.refresh(reason: .user) }
        for _ in 0..<100 where !model.isRefreshing { try await Task.sleep(for: .milliseconds(5)) }
        XCTAssertTrue(model.isRefreshing)
        model.clearCache()
        XCTAssertNil(model.snapshot)
        await refresh.value
        for _ in 0..<100 {
            if model.hasLoaded && !model.isRefreshing { break }
            try await Task.sleep(for: .milliseconds(10))
        }
        XCTAssertTrue(model.hasLoaded)
        XCTAssertEqual(model.snapshot?.providers.first?.windows, [])
        XCTAssertEqual(UsageCache.load(from: url)?.providers.first?.windows, [])
    }
}

private struct TransientProvider: UsageProvider {
    let id = "antigravity"
    let name = "Antigravity"
    let executableName = "agy"
    let signInCommand = "agy"
    let allowsPersistedReadings = false
    func read(previous: ProviderUsage?) -> ProviderUsage {
        ProviderUsage(id: id, name: name, installed: true, authenticated: true,
            windows: [UsageWindow(label: "Gemini · Weekly", remainingPercent: 42, resetsAt: nil)],
            updatedAt: Date(), condition: .ready)
    }
}

private struct FailingProvider: UsageProvider {
    let id = "test"
    let name = "Test"
    let executableName = "test"
    let signInCommand = "test login"
    func read(previous: ProviderUsage?) -> ProviderUsage {
        Thread.sleep(forTimeInterval: 0.08)
        var reading = ProviderUsage(id: id, name: name, installed: true, authenticated: true, accountKey: "same")
        reading.retainReading(from: previous, message: "Connection failed")
        return reading
    }
}
