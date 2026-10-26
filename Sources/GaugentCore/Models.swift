import CryptoKit
import Foundation

/// One allowance window reported by a provider, such as a 5-hour session or a weekly limit.
public struct UsageWindow: Codable, Equatable, Sendable, Identifiable {
    public let label: String
    /// Share of the window still available, from 0 to 100.
    public let remainingPercent: Double
    /// When the provider says the window replenishes. `nil` when it did not say.
    public let resetsAt: Date?

    public var id: String { label }

    public init(label: String, remainingPercent: Double, resetsAt: Date?) {
        self.label = String(label.prefix(80))
        self.remainingPercent = min(100, max(0, remainingPercent))
        self.resetsAt = resetsAt
    }

    /// A window whose reset time has passed is awaiting a fresh reading, not replenished.
    public func isExpired(at now: Date = Date()) -> Bool {
        guard let resetsAt else { return false }
        return resetsAt <= now
    }
}

public enum ProviderCondition: String, Codable, Sendable {
    case notInstalled
    case signedOut
    case unsupported
    case ready
    case error
}

/// Everything gaugent knows about one tool's subscription allowance.
public struct ProviderUsage: Codable, Equatable, Sendable, Identifiable {
    public let id: String
    public let name: String
    public var installed: Bool
    public var authenticated: Bool
    public var plan: String
    public var windows: [UsageWindow]
    public var notes: [String]
    public var updatedAt: Date?
    public var condition: ProviderCondition
    public var message: String
    /// Hashed identity of the signed-in account. Never the email or token itself.
    public var accountKey: String?
    /// When the provider was last asked, successful or not.
    public var attemptedAt: Date?
    /// Explicit provider block; optional for compatibility with older cached readings.
    public var limitReached: Bool?
    /// Consecutive refreshes whose live read failed; drives the automatic backoff.
    public var failureStreak: Int

    public init(
        id: String,
        name: String,
        installed: Bool = false,
        authenticated: Bool = false,
        plan: String = "",
        windows: [UsageWindow] = [],
        notes: [String] = [],
        updatedAt: Date? = nil,
        condition: ProviderCondition = .notInstalled,
        message: String = "",
        accountKey: String? = nil,
        attemptedAt: Date? = nil,
        failureStreak: Int = 0,
        limitReached: Bool? = nil
    ) {
        self.id = id
        self.name = name
        self.installed = installed
        self.authenticated = authenticated
        self.plan = plan
        self.windows = windows
        self.notes = notes
        self.updatedAt = updatedAt
        self.condition = condition
        self.message = message
        self.accountKey = accountKey
        self.attemptedAt = attemptedAt
        self.failureStreak = failureStreak
        self.limitReached = limitReached
    }

    /// Base interval between automatic attempts after a failure; doubles per failure up to `maximumBackoff`.
    public static let baseBackoff: TimeInterval = 300
    public static let maximumBackoff: TimeInterval = 3600

    /// Earliest time an automatic refresh should ask this provider again, or `nil` for right away.
    public func nextAutomaticAttempt() -> Date? {
        guard failureStreak > 0, let attemptedAt else { return nil }
        let exponent = min(failureStreak - 1, 10)
        let wait = min(Self.maximumBackoff, Self.baseBackoff * pow(2, Double(exponent)))
        return attemptedAt.addingTimeInterval(wait)
    }

    /// Readings older than this, or taken by a failed refresh, must never drive the low-allowance indicator.
    public static let staleAfter: TimeInterval = 600

    public func isStale(at now: Date = Date()) -> Bool {
        guard condition != .error, let updatedAt else { return true }
        let age = now.timeIntervalSince(updatedAt)
        return age < 0 || age > Self.staleAfter
    }

    public func liveWindows(at now: Date = Date()) -> [UsageWindow] {
        windows.filter { !$0.isExpired(at: now) }
    }

    /// Smallest remaining share among windows that are still counting down, or `nil`.
    public func lowestRemaining(at now: Date = Date()) -> Double? {
        liveWindows(at: now).map(\.remainingPercent).min()
    }

    /// Keeps the last good reading after a failed refresh, but only for the same account.
    ///
    /// A different or unknown account must never inherit someone else's numbers.
    public mutating func retainReading(from previous: ProviderUsage?, message: String) {
        if let previous, let accountKey, accountKey == previous.accountKey {
            windows = previous.windows
            notes = previous.notes
            updatedAt = previous.updatedAt
        }
        condition = .error
        self.message = message
        failureStreak = (previous?.failureStreak ?? 0) + 1
    }

    public var planLabel: String {
        if !authenticated {
            return condition == .error ? "Unavailable" : "Not signed in"
        }
        if id == "codex" {
            // Codex account/read uses internal IDs for the three ChatGPT Pro tiers.
            let proTiers = ["prolite": "Pro $100", "pro": "Pro $200", "promax": "Pro $500"]
            if let label = proTiers[plan.lowercased()] { return label }
        }
        let names = [
            "pro": "Pro", "plus": "Plus", "max": "Max",
            "max_5x": "Max 5×", "max_20x": "Max 20×", "free": "Free", "team": "Team",
            "business": "Business", "enterprise": "Enterprise", "edu": "Edu"
        ]
        if let known = names[plan.lowercased()] { return known }
        if plan.isEmpty || plan == "unknown" { return "Signed in" }
        return plan.replacingOccurrences(of: "_", with: " ")
    }
}

public struct UsageSnapshot: Codable, Equatable, Sendable {
    public static let currentVersion = 1

    public var version: Int
    public var checkedAt: Date
    public var providers: [ProviderUsage]

    public init(version: Int = UsageSnapshot.currentVersion, checkedAt: Date, providers: [ProviderUsage]) {
        self.version = version
        self.checkedAt = checkedAt
        self.providers = providers
    }

    public func provider(_ id: String) -> ProviderUsage? {
        providers.first { $0.id == id }
    }
}

public enum AccountIdentity {
    /// Stable, non-reversible key for an account. Returns `nil` when nothing identifies the account.
    public static func key(_ fields: [String: String?]) -> String? {
        let present = fields.compactMapValues { $0 }.filter { !$0.value.isEmpty }
        guard !present.isEmpty else { return nil }
        let serialized = present.keys.sorted().map { "\($0)=\(present[$0]!)" }.joined(separator: "\n")
        let digest = SHA256.hash(data: Data(serialized.utf8))
        return digest.map { String(format: "%02x", $0) }.joined()
    }
}

/// Finite numbers only. Callers apply their field's sign and range constraints.
public func finiteNumber(_ value: Any?) -> Double? {
    if let number = value as? NSNumber {
        guard CFGetTypeID(number) != CFBooleanGetTypeID() else { return nil }
        let double = number.doubleValue
        return double.isFinite ? double : nil
    }
    return nil
}

public func resetDate(_ value: Any?) -> Date? {
    if let seconds = finiteNumber(value), seconds > 0, seconds <= Date.distantFuture.timeIntervalSince1970 {
        return Date(timeIntervalSince1970: seconds)
    }
    if let text = value as? String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        if let date = formatter.date(from: text) { return date }
        formatter.formatOptions = [.withInternetDateTime]
        return formatter.date(from: text)
    }
    return nil
}

/// Builds a window from a used percentage, rejecting anything that is not a real number.
public func usageWindow(label: String, usedPercent: Any?, resetsAt: Any?) -> UsageWindow? {
    guard let used = finiteNumber(usedPercent), used >= 0 else { return nil }
    return UsageWindow(label: label, remainingPercent: max(0, 100 - used), resetsAt: resetDate(resetsAt))
}

/// Shared presentation state: authentication alone does not imply usable quota data.
public struct UsageOverview {
    public let providers: [ProviderUsage]
    public let now: Date

    public init(providers: [ProviderUsage], now: Date = Date()) {
        self.providers = providers
        self.now = now
    }

    public var blockedProvider: ProviderUsage? {
        providers.first { !$0.isStale(at: now) && $0.limitReached == true }
    }

    public var lowest: (provider: ProviderUsage, window: UsageWindow)? {
        providers.filter { !$0.isStale(at: now) }
            .flatMap { provider in provider.liveWindows(at: now).map { (provider: provider, window: $0) } }
            .min { $0.window.remainingPercent < $1.window.remainingPercent }
    }

    public var currentCount: Int {
        providers.filter { !$0.isStale(at: now) && !$0.liveWindows(at: now).isEmpty }.count
    }

    public var statusText: String {
        if providers.isEmpty { return "No tools enabled" }
        if let blockedProvider { return "\(blockedProvider.name) · limit reached" }
        if currentCount == 0 { return "No current readings" }
        return "\(currentCount) of \(providers.count) tools current"
    }
}

public extension ProviderUsage {
    var connectionStatus: String {
        switch condition {
        case .notInstalled: return "Not installed"
        case .signedOut: return "Not signed in"
        case .unsupported: return "Allowance unavailable for this account"
        case .ready: return limitReached == true ? "Limit reached" : "\(planLabel) · \(windows.count) allowance windows"
        case .error: return authenticated ? "Signed in · refresh failed" : "Connection failed · sign-in status unknown"
        }
    }
}
