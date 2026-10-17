import AppKit
import Combine
import Foundation
import GaugentCore
import ServiceManagement

@MainActor
final class AppModel: ObservableObject {
    nonisolated static let bundleIdentifier = "com.shivamx96.gaugent"

    /// Automatic refreshes and opening the panel reuse a reading younger than this.
    static let ambientRefreshInterval: TimeInterval = 300
    /// Opening the panel refreshes only if the last reading is older than this.
    static let panelRefreshInterval: TimeInterval = 60

    @Published private(set) var snapshot: UsageSnapshot?
    @Published private(set) var isRefreshing = false
    @Published private(set) var hasLoaded = false
    @Published var actionMessage: String?
    @Published private(set) var loginMessage: String?
    private var cacheGeneration = 0
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
        didSet { save(enabledProviderIDs, for: Keys.enabledProviderIDs); Task { await refresh(reason: .user) } }
    }

    let collector: UsageCollector
    private let defaults: UserDefaults
    private let storageURL: URL?

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

    init(collector: UsageCollector = .standard, defaults: UserDefaults = .standard,
         storageURL: URL? = AppModel.cacheURL(), startAutomatically: Bool = true) {
        self.collector = collector
        self.defaults = defaults
        self.storageURL = storageURL
        appearance = GaugentAppearance(rawValue: defaults.string(forKey: Keys.appearance) ?? "") ?? .system
        menuBarDisplayMode = MenuBarDisplayMode(rawValue: defaults.string(forKey: Keys.menuBarDisplayMode) ?? "") ?? .glyphAndPercent
        dimIconWhenIdle = defaults.object(forKey: Keys.dimIconWhenIdle) == nil ? true : defaults.bool(forKey: Keys.dimIconWhenIdle)
        refreshAutomatically = defaults.object(forKey: Keys.refreshAutomatically) == nil ? true : defaults.bool(forKey: Keys.refreshAutomatically)
        lowThreshold = defaults.object(forKey: Keys.lowThreshold) == nil ? 20 : defaults.integer(forKey: Keys.lowThreshold)
        enabledProviderIDs = defaults.stringArray(forKey: Keys.enabledProviderIDs) ?? collector.providers.map(\.id)
        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled

        if let cacheURL = storageURL, let cached = UsageCache.load(from: cacheURL) {
            snapshot = cached
        }
        if startAutomatically {
            configureTimers()
            Task { [weak self] in await self?.refresh(reason: .automatic) }
        }
    }

    // MARK: Derived state

    var enabledProviders: Set<String> { Set(enabledProviderIDs) }

    /// Enabled tools, including missing installations so setup actions remain discoverable.
    var visibleProviders: [ProviderUsage] {
        (snapshot?.providers ?? []).filter { enabledProviders.contains($0.id) }
    }

    var connectedCount: Int { visibleProviders.filter(\.authenticated).count }

    var overview: UsageOverview { UsageOverview(providers: visibleProviders, now: now) }
    var lowestRemaining: Double? { overview.lowest?.window.remainingPercent }
    var needsAttention: Bool {
        overview.blockedProvider != nil || (lowestRemaining.map { $0 <= Double(lowThreshold) } ?? false)
    }
    var headline: String {
        if let blocked = overview.blockedProvider { return "\(blocked.name) · limit reached" }
        if let lowest = overview.lowest { return "\(lowest.provider.name) · \(lowest.window.label)" }
        return enabledProviders.isEmpty ? "No tools enabled" : "Allowance unavailable"
    }

    var lastRefresh: Date? { snapshot?.checkedAt }

    var applicationVersion: String {
        let build = Bundle.main.bundleIdentifier == Self.bundleIdentifier
            ? Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1" : "1"
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

    enum RefreshReason {
        /// The timer or app start: honours per-provider backoff.
        case automatic
        /// The panel opened: reuses a reading younger than a minute, then behaves like `automatic`.
        case panelOpened
        /// ⌘R or a button: asks every provider now, backoff or not.
        case user
    }

    /// Reads every enabled provider according to `reason`.
    ///
    /// Overlapping calls fold into one follow-up so two panel opens do not spawn four CLIs.
    func refresh(reason: RefreshReason) async {
        if reason == .panelOpened, let lastRefresh, now.timeIntervalSince(lastRefresh) < Self.panelRefreshInterval, hasLoaded { return }
        if isRefreshing {
            pendingRefresh = pendingRefresh || reason == .user
            return
        }
        isRefreshing = true
        defer { isRefreshing = false }

        let generation = cacheGeneration
        let previous = snapshot
        let enabled = enabledProviders
        let collector = collector
        let fresh = await collector.collect(previous: previous, enabled: enabled, userInitiated: reason == .user)
        guard generation == cacheGeneration else {
            pendingRefresh = false
            Task { [weak self] in await self?.refresh(reason: .user) }
            return
        }
        snapshot = fresh
        now = Date()
        hasLoaded = true
        if actionMessage == "Saved readings cleared. Fetching new readings…" {
            actionMessage = "Saved readings reset. " + overview.statusText + "."
        }
        if let cacheURL = storageURL {
            UsageCache.save(fresh, to: cacheURL)
        }
        if pendingRefresh {
            pendingRefresh = false
            Task { [weak self] in await self?.refresh(reason: .user) }
        }
    }

    /// Text for a provider that is waiting out a backoff, or `nil`.
    func nextAttemptText(_ provider: ProviderUsage) -> String? {
        guard let next = provider.nextAutomaticAttempt(), next > now, refreshAutomatically else { return nil }
        let minutes = max(1, Int((next.timeIntervalSince(now) / 60).rounded(.up)))
        return "Automatic retry in about \(minutes)m"
    }

    private func configureTimers() {
        refreshTimer?.cancel()
        clockTimer = Timer.publish(every: 15, on: .main, in: .common)
            .autoconnect()
            .sink { [weak self] date in self?.now = date }
        if refreshAutomatically {
            refreshTimer = Timer.publish(every: Self.ambientRefreshInterval, on: .main, in: .common)
                .autoconnect()
                .sink { [weak self] _ in Task { await self?.refresh(reason: .automatic) } }
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
            loginMessage = "Could not change launch at login. Try again from an installed copy of gaugent. \(error.localizedDescription)"
            return
        }
        isLaunchAtLoginEnabled = SMAppService.mainApp.status == .enabled
        loginMessage = SMAppService.mainApp.status == .requiresApproval
            ? "Allow gaugent in System Settings → General → Login Items."
            : (isLaunchAtLoginEnabled ? "Launch at login enabled." : "Launch at login disabled.")
    }

    func setGlobalShortcutRegistered(_ registered: Bool) {
        isGlobalShortcutRegistered = registered
    }

    func clearCache() {
        do {
            if let url = storageURL, FileManager.default.fileExists(atPath: url.path) {
                try FileManager.default.removeItem(at: url)
            }
            cacheGeneration += 1
            snapshot = nil
            hasLoaded = false
            actionMessage = "Saved readings cleared. Fetching new readings…"
            Task { await refresh(reason: .user) }
        } catch {
            actionMessage = "Could not clear saved readings: \(error.localizedDescription)"
        }
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
        actionMessage = "Diagnostics copied."
    }

    /// Copies a sign-in command and brings up Terminal so the user can paste it.
    func copyAndOpenTerminal(_ command: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(command, forType: .string)
        let terminal = URL(fileURLWithPath: "/System/Applications/Utilities/Terminal.app")
        actionMessage = "Command copied. Paste it in Terminal, press Return, then refresh after signing in."
        NSWorkspace.shared.openApplication(at: terminal, configuration: NSWorkspace.OpenConfiguration()) { [weak self] _, error in
            if error != nil { Task { @MainActor in self?.actionMessage = "Command copied. Open Terminal and paste it to sign in." } }
        }
    }

    func openInstallationGuide(for providerID: String) {
        let address = providerID == "codex"
            ? "https://github.com/openai/codex#installation--setup"
            : "https://github.com/anthropics/claude-code#installation"
        open(URL(string: address)!)
    }

    func open(_ url: URL) { NSWorkspace.shared.open(url) }

    private func save(_ value: Any, for key: String) { defaults.set(value, forKey: key) }

    nonisolated static func cacheURL() -> URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appendingPathComponent(bundleIdentifier, isDirectory: true)
            .appendingPathComponent("usage.json")
    }
}
