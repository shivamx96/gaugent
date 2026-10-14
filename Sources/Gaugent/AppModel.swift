import AppKit
import Combine
import Foundation
import GaugentCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    static let bundleIdentifier = "com.shivamx96.gaugent"

    /// Automatic refreshes and opening the panel reuse a reading younger than this.
    static let ambientRefreshInterval: TimeInterval = 300
    /// Opening the panel refreshes only if the last reading is older than this.
    static let panelRefreshInterval: TimeInterval = 60

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasLoaded = false
    @Published private(set) var now = Date()
    @Published private(set) var isLaunchAtLoginEnabled: Bool
    @Published private(set) var isGlobalShortcutRegistered = false

    @Published var appearance: GaugentAppearance { didSet { save(appearance.rawValue, for: Keys.appearance) } }
    @Published var menuBarDisplayMode: MenuBarDisplayMode { didSet { save(menuBarDisplayMode.rawValue, for: Keys.menuBarDisplayMode) } }
    @Published var dimIconWhenIdle: Bool { didSet { save(dimIconWhenIdle, for: Keys.dimIconWhenIdle) } }
    @Published var refreshAutomatically: Bool {
        didSet { save(refreshAutomatically, for: Keys.refreshAutomatically); configureTimers() }
    }
    @Published var lowThreshold: Int { didSet { save(lowThreshold, for: Keys.lowThreshold) } }
    @Published var enabledProviderIDs: [String] {
        didSet { save(enabledProviderIDs, for: Keys.enabledProviderIDs); Task { await refresh(force: true) } }
    }

    let collector = UsageCollector.standard

    private var refreshTimer: AnyCancellable?
    private var clockTimer: AnyCancellable?
    private var pendingRefresh = false

    private enum Keys {
        static let appearance = "appearance"
        static let menuBarDisplayMode = "menuBarDisplayMode"
        static let dimIconWhenIdle = "dimIconWhenIdle"
        static let refreshAutomatically = "refreshAutomatically"
        static let lowThreshold = "lowThreshold"
        static let enabledProviderIDs = "enabledProviderIDs"
    }

    init() {
        let defaults = UserDefaults.standard
        appearance = GaugentAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        menuBarDisplayMode = MenuBarDisplayMode(rawValue: defaults.string(forKey: Keys.menuBarDisplayMode) ?? "") ?? .glyphAndPercent
        dimIconWhenIdle = defaults.object(forKey: Keys.dimIconWhenIdle) == nil ? true : defaults.bool(forKey: Keys.dimIconWhenIdle)
        refreshAutomatically = defaults.object(forKey: Keys.refreshAutomatically) == nil ? true : defaults.bool(forKey: Keys.refreshAutomatically)
        lowThreshold = defaults.object(forKey: Keys.lowThreshold) == nil ? 20 : defaults.integer(forKey: Keys.lowThreshold)
        enabledProviderIDs = defaults.stringArray(forKey: Keys.enabledProviderIDs) ?? UsageCollector.standard.providers.map(\.id)
        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled

        if let cacheURL = Self.cacheURL(), let cached = UsageCache.load(from: cacheURL) {
            snapshot = cached
        }
        configureTimers()
        Task { [weak self] in await self?.refresh(force: true) }
    }

    // MARK: Derived state

    var enabledProviders: Set<String> { Set(enabledProviderIDs) }

    /// Providers worth a card: enabled and found on this Mac, in configured order.
    var visibleProviders: [ProviderUsage] {
        (snapshot?.providers ?? []).filter { enabledProviders.contains($0.id) && $0.installed }
    }

    var connectedCount: Int { visibleProviders.filter(\.authenticated).count }

    /// Lowest remaining share among fresh, non-expired windows; stale readings never count.
    var lowestRemaining: Double? {
        visibleProviders
            .filter { !$0.isStale(at: now) }
            .compactMap { $0.lowestRemaining(at: now) }
            .min()
    }

    var needsAttention: Bool {
        guard let lowestRemaining else { return false }
        return lowestRemaining <= Double(lowThreshold)
    }

    var lastRefresh: Date? { snapshot?.checkedAt }

    var applicationVersion: String {
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "gaugent \(GaugentVersion.string) (build \(build))"
    }

    func isStale(_ provider: ProviderUsage) -> Bool { provider.isStale(at: now) }

    func isExpired(_ window: UsageWindow) -> Bool { window.isExpired(at: now) }

    func resetText(_ window: UsageWindow) -> String {
        guard let resetsAt = window.resetsAt else { return "Reset time unavailable" }
        let minutes = Int((resetsAt.timeIntervalSince(now) / 60).rounded(.up))
        if minutes <= 0 { return "Reset time passed · awaiting an update" }
        if minutes < 60 { return "Resets in \(minutes)m" }
        if minutes < 1440 { return "Resets in \(minutes / 60)h \(minutes % 60)m" }
        return "Resets in \(minutes / 1440)d \(minutes % 1440 / 60)h"
    }

    func ageText(_ provider: ProviderUsage) -> String {
        guard let updatedAt = provider.updatedAt else { return "" }
        let minutes = max(0, Int(now.timeIntervalSince(updatedAt) / 60))
        let when = minutes < 1 ? "just now" : minutes < 60 ? "\(minutes)m ago" : "\(minutes / 60)h ago"
        return (isStale(provider) ? "Last reported " : "Updated ") + when
    }

    // MARK: Refresh

    /// Reads every enabled provider. Without `force`, a recent reading is reused.
    ///
    /// Overlapping calls fold into one follow-up so two panel opens do not spawn four CLIs.
    func refresh(force: Bool) async {
        if !force, let lastRefresh, now.timeIntervalSince(lastRefresh) < Self.panelRefreshInterval, hasLoaded { return }
        if isRefreshing {
            pendingRefresh = pendingRefresh || force
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let previous = snapshot
        let enabled = enabledProviders
        let collector = collector
        let fresh = await collector.collect(previous: previous, enabled: enabled)
        snapshot = fresh
        now = Date()
        hasLoaded = true
        if let cacheURL = Self.cacheURL() {
            UsageCache.save(fresh, to: cacheURL)
        }
        if pendingRefresh {
            pendingRefresh = false
            Task { [weak self] in await self?.refresh(force: true) }
        }
    }

    private func configureTimers() {
        refreshTimer?.cancel()
        clockTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.now = date }
        if refreshAutomatically {
            refreshTimer = Timer.publish(every: Self.ambientRefreshInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in Task { await self?.refresh(force: true) } }
        }
    }

    // MARK: Settings actions

    func setProvider(_ id: String, enabled: Bool) {
        var ids = enabledProviderIDs
        ids.removeAll { $0 == id }
        if enabled {
            ids = collector.providers.map(\.id).filter { $0 == id || ids.contains($0) }
        }
        enabledProviderIDs = ids
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled { try SMAppService.mainApp.register() } else { try SMAppService.mainApp.unregister() }
        } catch {
            NSSound.beep()
        }
        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
    }

    func setGlobalShortcutRegistered(_ registered: Bool) {
        isGlobalShortcutRegistered = registered
    }

    func clearCache() {
        guard let url = Self.cacheURL() else { return }
        try? FileManager.default.removeItem(at: url)
    }

    func copyDiagnostics() {
        var lines = [applicationVersion, "macOS \(ProcessInfo.processInfo.operatingSystemVersionString)"]
        for provider in collector.providers {
            let path = ExecutableLocator.locate(provider.executableName) ?? "not found"
            let reading = snapshot?.provider(provider.id)
            let state = reading.map { "\($0.condition.rawValue) · \($0.planLabel) · \($0.windows.count) windows" } ?? "not read"
            lines.append("\(provider.name): \(path) · \(state)")
        }
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(lines.joined(separator: "\n"), forType: .string)
    }

    /// Copies a sign-in command and brings up Terminal so the user can paste it.
    func copyAndOpenTerminal(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration())
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    private func save(_ value: Any, for key: String) { UserDefaults.standard.set(value, forKey: key) }

    static func cacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("usage.json")
    }
}
