import Foundation

/// Reads Codex allowances through `codex app-server`'s account RPCs.
///
/// The app server answers `account/read` and `account/rateLimits/read` from the CLI's own
/// session without starting a thread or a turn, so no token ever passes through gaugent.
public struct CodexProvider: UsageProvider {
    public let id = "codex"
    public let name = "Codex"
    public let executableName = "codex"
    public let signInCommand = "codex login"

    private let preferredPath: String?
    private let resolver: ExecutableResolver
    private let home: URL
    private let timeout: TimeInterval

    public init(
        preferredPath: String? = nil,
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        timeout: TimeInterval = 15,
        resolver: @escaping ExecutableResolver = ExecutableLocator.locate
    ) {
        self.preferredPath = preferredPath
        self.resolver = resolver
        self.home = home
        self.timeout = timeout
    }

    public func read(previous: ProviderUsage?) -> ProviderUsage {
        guard let executable = resolver(executableName, preferredPath, home) else {
            return unavailable(installed: false)
        }
        var usage = unavailable(installed: true)
        let client = LineProcessClient(executable: executable, arguments: ["app-server"], currentDirectory: home, timeout: timeout)
        defer { client.terminate() }
        do {
            try client.start()
            let rpc = JSONRPCSession(client: client)
            _ = try rpc.request("initialize", params: ["clientInfo": ["name": "gaugent", "version": GaugentVersion.string]])
            try rpc.notify("initialized")
            guard let account = try rpc.request("account/read", params: ["refreshToken": false])["account"] as? [String: Any] else {
                return usage
            }
            usage.authenticated = true
            usage.accountKey = AccountIdentity.key(["provider": "codex", "email": account["email"] as? String])
            usage.plan = account["planType"] as? String ?? ""
            guard account["type"] as? String == "chatgpt" else {
                usage.condition = .unsupported
                usage.message = "Subscription allowance is unavailable for this login type."
                return usage
            }
            let payload = try rpc.request("account/rateLimits/read")
            let reading = CodexRateLimits.parse(payload)
            usage.limitReached = reading.limitReached
            usage.windows = reading.windows
            usage.notes = reading.notes
            usage.updatedAt = Date()
            usage.condition = .ready
            usage.failureStreak = 0
            if reading.limitReached {
                usage.message = "Your account has reached a usage or spending limit."
            } else if reading.windows.isEmpty {
                usage.message = "No allowance windows were reported for this account."
            } else {
                usage.message = ""
            }
        } catch {
            usage.retainReading(from: previous, message: "Could not refresh Codex usage. Try again shortly.")
        }
        return usage
    }
}

public enum CodexRateLimits {
    public struct Reading: Equatable, Sendable {
        public var windows: [UsageWindow]
        public var notes: [String]
        public var limitReached: Bool
    }

    public static func parse(_ payload: [String: Any]) -> Reading {
        var buckets = (payload["rateLimitsByLimitId"] as? [String: Any])?.compactMapValues { $0 as? [String: Any] } ?? [:]
        if buckets.isEmpty, let single = payload["rateLimits"] as? [String: Any] {
            buckets = ["codex": single]
        }
        // "codex" is the ordinary allowance; keep it first, then any named buckets alphabetically.
        let keys = buckets.keys.sorted { lhs, rhs in
            if lhs == "codex" { return true }
            if rhs == "codex" { return false }
            return lhs < rhs
        }

        var windows: [UsageWindow] = []
        var notes: [String] = []
        var limitReached = payload["ordinaryUsageAllowed"] as? Bool == false

        for key in keys {
            guard let bucket = buckets[key] else { continue }
            let prefix = keys.count > 1 ? "\(bucket["limitName"] as? String ?? key) · " : ""
            for (field, fallback) in [("primary", "Primary"), ("secondary", "Secondary")] {
                guard let data = bucket[field] as? [String: Any] else { continue }
                let label = prefix + durationLabel(minutes: finiteNumber(data["windowDurationMins"]), fallback: fallback)
                if let window = usageWindow(label: label, usedPercent: data["usedPercent"], resetsAt: data["resetsAt"]) {
                    windows.append(window)
                }
            }
            if let spend = bucket["individualLimit"] as? [String: Any], let remaining = finiteNumber(spend["remainingPercent"]) {
                if let window = usageWindow(label: prefix + "Spend limit", usedPercent: 100 - remaining, resetsAt: spend["resetsAt"]) {
                    windows.append(window)
                }
            }
            if bucket["rateLimitReachedType"] != nil && !(bucket["rateLimitReachedType"] is NSNull) {
                limitReached = true
            }
            if bucket["spendControlReached"] as? Bool == true {
                limitReached = true
            }
            if let credits = bucket["credits"] as? [String: Any] {
                if credits["unlimited"] as? Bool == true {
                    notes.append(prefix + "Unlimited credits")
                } else if credits["hasCredits"] as? Bool == true, let balance = credits["balance"] as? String, !balance.isEmpty {
                    notes.append(prefix + "Credit balance \(balance)")
                }
            }
        }

        if let resets = payload["rateLimitResetCredits"] as? [String: Any],
           let available = finiteNumber(resets["availableCount"]), available >= 1 {
            let count = Int(available)
            notes.append(count == 1 ? "1 full reset available" : "\(count) full resets available")
        }

        return Reading(windows: windows, notes: notes, limitReached: limitReached)
    }

    /// Provider-driven window names: "5-hour", "7-day", or the raw minutes when unusual.
    public static func durationLabel(minutes: Double?, fallback: String) -> String {
        guard let minutes, minutes > 0 else { return fallback }
        func format(_ value: Double) -> String {
            value == value.rounded() ? String(Int(value)) : String(value)
        }
        if minutes.truncatingRemainder(dividingBy: 1440) == 0 { return "\(format(minutes / 1440))-day" }
        if minutes.truncatingRemainder(dividingBy: 60) == 0 { return "\(format(minutes / 60))-hour" }
        return "\(format(minutes))-minute"
    }
}

public enum GaugentVersion {
    public static var string: String {
        guard Bundle.main.bundleIdentifier == "com.shivamx96.gaugent" else { return "0.1.0" }
        return Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "0.1.0"
    }
}
