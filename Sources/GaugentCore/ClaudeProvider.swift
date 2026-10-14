import Foundation

/// Reads Claude Code allowances through the CLI's stream-JSON control channel.
///
/// `claude auth status --json` identifies the login without exposing credentials. The usage
/// itself comes from the experimental `get_usage` control request, sent to a print-mode
/// process started in safe mode with no tools, no MCP servers, and no session persistence.
/// No user turn is ever sent, so nothing is spent and nothing is saved.
public struct ClaudeProvider: UsageProvider {
    public let id = "claude"
    public let name = "Claude Code"
    public let executableName = "claude"
    public let signInCommand = "claude auth login"

    private let preferredPath: String?
    private let resolver: ExecutableResolver
    private let runner: any ProcessRunning
    private let home: URL
    private let configDirectory: URL?
    private let timeout: TimeInterval

    public init(
        preferredPath: String? = nil,
        runner: any ProcessRunning = ProcessRunner(timeout: 10),
        home: URL = FileManager.default.homeDirectoryForCurrentUser,
        configDirectory: URL? = nil,
        timeout: TimeInterval = 20,
        resolver: @escaping ExecutableResolver = ExecutableLocator.locate
    ) {
        self.preferredPath = preferredPath
        self.resolver = resolver
        self.runner = runner
        self.home = home
        self.configDirectory = configDirectory
        self.timeout = timeout
    }

    public static let controlArguments = [
        "--print", "--input-format", "stream-json", "--output-format", "stream-json", "--verbose",
        "--no-session-persistence", "--safe-mode", "--tools", "", "--strict-mcp-config",
        "--mcp-config", #"{"mcpServers":{}}"#
    ]

    public func read(previous: ProviderUsage?) -> ProviderUsage {
        guard let executable = resolver(executableName, preferredPath, home) else {
            return unavailable(installed: false)
        }
        var usage = unavailable(installed: true)
        var lastAuthentication: ClaudeAuthentication?
        do {
            let auth = try authentication(executable: executable)
            lastAuthentication = auth
            usage.authenticated = auth.loggedIn
            usage.accountKey = auth.accountKey
            usage.plan = ClaudePlan.resolve(auth: auth, configDirectory: resolvedConfigDirectory)
            guard auth.loggedIn else { return usage }
            guard ["claude.ai", "oauth"].contains(auth.authMethod) else {
                usage.condition = .unsupported
                usage.message = "Subscription allowance is unavailable for this login type."
                return usage
            }

            let client = LineProcessClient(executable: executable, arguments: Self.controlArguments, currentDirectory: home, timeout: timeout)
            defer { client.terminate() }
            try client.start()
            let control = ControlSession(client: client)
            _ = try control.request("initialize")
            let payload = try control.request("get_usage", params: ["skip_behaviors": true])

            guard payload["rate_limits_available"] as? Bool == true else {
                usage.condition = .unsupported
                usage.message = "Subscription allowance is unavailable for this account."
                return usage
            }
            guard let rates = payload["rate_limits"] as? [String: Any] else {
                // The CLI answers from its own usage endpoint; a null here means that fetch was
                // declined (usually a rate limit) and will likely succeed on a later refresh.
                fallBack(&usage, previous: previous, auth: auth, message: "Claude Code could not fetch usage right now. It is retried automatically.")
                return usage
            }
            usage.windows = ClaudeRateLimits.windows(rates)
            usage.notes = ClaudeRateLimits.notes(rates)
            usage.updatedAt = Date()
            usage.condition = .ready
            usage.message = usage.windows.isEmpty ? "No allowance windows were reported for this account." : ""
        } catch {
            fallBack(&usage, previous: previous, auth: usage.authenticated ? lastAuthentication : nil,
                     message: "Could not refresh Claude usage. Retry or update Claude Code if this persists.")
        }
        return usage
    }

    /// Uses the newest reading available when a live fetch fails: the CLI's own persisted
    /// snapshot in `.claude.json` or the previous reading, whichever is fresher.
    ///
    /// The snapshot is what the CLI shows in its own usage screen, written after its last
    /// successful fetch. It carries quota numbers only, and is used solely when it belongs to
    /// the account the CLI just reported. Its fetch time becomes the reading's age, so an old
    /// snapshot shows dimmed and never drives the low-allowance warning.
    private func fallBack(_ usage: inout ProviderUsage, previous: ProviderUsage?, auth: ClaudeAuthentication?, message: String) {
        usage.retainReading(from: previous, message: message)
        guard let auth, let snapshot = ClaudeUsageSnapshot.load(configDirectory: resolvedConfigDirectory, auth: auth) else { return }
        if let retained = usage.updatedAt, retained >= snapshot.fetchedAt { return }
        usage.windows = ClaudeRateLimits.windows(snapshot.rates)
        usage.notes = ClaudeRateLimits.notes(snapshot.rates)
        usage.updatedAt = snapshot.fetchedAt
        usage.condition = .ready
        usage.message = "Live fetch unavailable; showing the reading Claude Code last fetched itself."
    }

    private var resolvedConfigDirectory: URL {
        if let configDirectory { return configDirectory }
        if let path = ProcessInfo.processInfo.environment["CLAUDE_CONFIG_DIR"], !path.isEmpty {
            return URL(fileURLWithPath: path)
        }
        return home
    }

    private func authentication(executable: String) throws -> ClaudeAuthentication {
        let result = runner.run(executable: executable, arguments: ["auth", "status", "--json"], currentDirectory: home)
        guard let data = result.standardOutput.data(using: .utf8),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loggedIn = object["loggedIn"] as? Bool else {
            throw LineProcessError.requestFailed("auth status")
        }
        return ClaudeAuthentication(
            loggedIn: loggedIn,
            authMethod: object["authMethod"] as? String ?? "",
            email: object["email"] as? String,
            orgId: (object["orgId"] ?? object["organizationId"]) as? String,
            subscriptionType: object["subscriptionType"] as? String ?? "",
            accountKey: AccountIdentity.key([
                "provider": "claude",
                "email": object["email"] as? String,
                "orgId": object["orgId"] as? String,
                "organizationId": object["organizationId"] as? String,
                "authMethod": object["authMethod"] as? String,
                "apiProvider": object["apiProvider"] as? String,
                "configDirectory": object["configDirectory"] as? String
            ])
        )
    }
}

public struct ClaudeAuthentication: Equatable, Sendable {
    public var loggedIn: Bool
    public var authMethod: String
    public var email: String?
    public var orgId: String?
    public var subscriptionType: String
    public var accountKey: String?

    public init(loggedIn: Bool, authMethod: String, email: String?, orgId: String?, subscriptionType: String, accountKey: String?) {
        self.loggedIn = loggedIn
        self.authMethod = authMethod
        self.email = email
        self.orgId = orgId
        self.subscriptionType = subscriptionType
        self.accountKey = accountKey
    }
}

/// The usage reading Claude Code persists in `.claude.json` after its own successful fetch.
public struct ClaudeUsageSnapshot: Sendable {
    public let rates: [String: Any]
    public let fetchedAt: Date

    public static func load(configDirectory: URL, auth: ClaudeAuthentication) -> ClaudeUsageSnapshot? {
        guard let email = auth.email, let orgId = auth.orgId,
              let data = try? Data(contentsOf: configDirectory.appendingPathComponent(".claude.json")),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any],
              account["emailAddress"] as? String == email,
              account["organizationUuid"] as? String == orgId,
              let cached = object["cachedUsageUtilization"] as? [String: Any],
              let rates = cached["utilization"] as? [String: Any],
              let fetchedAtMs = finiteNumber(cached["fetchedAtMs"]), fetchedAtMs > 0 else { return nil }
        if let cachedAccount = cached["accountUuid"] as? String, let profileAccount = account["accountUuid"] as? String,
           cachedAccount != profileAccount {
            return nil
        }
        return ClaudeUsageSnapshot(rates: rates, fetchedAt: Date(timeIntervalSince1970: fetchedAtMs / 1000))
    }
}

public enum ClaudePlan {
    /// Distinguishes Max 5× from Max 20× using non-secret profile metadata in `.claude.json`.
    ///
    /// The tier is used only when the profile belongs to the account the CLI just reported,
    /// and unknown tiers stay plain "max".
    public static func resolve(auth: ClaudeAuthentication, configDirectory: URL) -> String {
        let plan = auth.subscriptionType
        guard plan == "max", let email = auth.email, let orgId = auth.orgId else { return plan }
        let url = configDirectory.appendingPathComponent(".claude.json")
        guard let data = try? Data(contentsOf: url),
              let object = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let account = object["oauthAccount"] as? [String: Any],
              account["emailAddress"] as? String == email,
              account["organizationUuid"] as? String == orgId else { return plan }
        let tier = (account["userRateLimitTier"] ?? account["organizationRateLimitTier"]) as? String
        switch tier {
        case "default_claude_max_5x": return "max_5x"
        case "default_claude_max_20x": return "max_20x"
        default: return plan
        }
    }
}

public enum ClaudeRateLimits {
    /// Prefers the server's named `limits` rows and keeps older field names as fallbacks.
    public static func windows(_ rates: [String: Any]) -> [UsageWindow] {
        var result: [UsageWindow] = []
        var labels = Set<String>()

        func add(_ label: String, _ data: Any?, usedKey: String = "utilization") {
            guard let data = data as? [String: Any], !labels.contains(label),
                  let window = usageWindow(label: label, usedPercent: data[usedKey], resetsAt: data["resets_at"]) else { return }
            labels.insert(label)
            result.append(window)
        }

        for row in rates["limits"] as? [[String: Any]] ?? [] {
            switch row["kind"] as? String {
            case "session":
                add("Session · 5-hour", row, usedKey: "percent")
            case "weekly_all":
                add("Weekly · All models", row, usedKey: "percent")
            case "weekly_scoped":
                if let model = ((row["scope"] as? [String: Any])?["model"] as? [String: Any])?["display_name"] as? String {
                    add("Weekly · \(model) only", row, usedKey: "percent")
                }
            default:
                continue
            }
        }

        add("Session · 5-hour", rates["five_hour"])
        add("Weekly · All models", rates["seven_day"])
        for row in rates["model_scoped"] as? [[String: Any]] ?? [] {
            if let model = row["display_name"] as? String {
                add("Weekly · \(model) only", row)
            }
        }
        add("Weekly · Opus only", rates["seven_day_opus"])
        add("Weekly · Sonnet only", rates["seven_day_sonnet"])
        return result
    }

    public static func notes(_ rates: [String: Any]) -> [String] {
        guard let extra = rates["extra_usage"] as? [String: Any], extra["is_enabled"] as? Bool == true else { return [] }
        let used = finiteNumber(extra["used_credits"])
        let limit = finiteNumber(extra["monthly_limit"])
        switch (used, limit) {
        case let (used?, limit?) where limit > 0:
            return ["Extra usage on · \(currency(used)) of \(currency(limit)) this month"]
        case let (used?, _):
            return ["Extra usage on · \(currency(used)) this month"]
        default:
            return ["Extra usage on"]
        }
    }

    private static func currency(_ value: Double) -> String {
        value == value.rounded() ? "$\(Int(value))" : String(format: "$%.2f", value)
    }
}
