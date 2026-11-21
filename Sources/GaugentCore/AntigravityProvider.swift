import Foundation

/// Reads the CLI's built-in quota command, never a model prompt. Older CLIs treated
/// slash commands as prompts, so inspect their local help and changelog first.
public struct AntigravityProvider: UsageProvider {
    public let id = "antigravity"
    public let name = "Antigravity"
    public let executableName = "agy"
    public let signInCommand = "agy"
    // /usage does not identify the account. Never reuse or persist these readings.
    public let allowsPersistedReadings = false

    private let preferredPath: String?
    private let runner: any ProcessRunning
    private let resolver: ExecutableResolver
    private let home: URL

    public init(preferredPath: String? = nil, runner: any ProcessRunning = ProcessRunner(timeout: 20),
                home: URL = FileManager.default.homeDirectoryForCurrentUser,
                resolver: @escaping ExecutableResolver = ExecutableLocator.locate) {
        self.preferredPath = preferredPath
        self.runner = runner
        self.home = home
        self.resolver = resolver
    }

    public static let usageArguments = [
        "--print", "/usage", "--output-format", "json", "--print-timeout", "15s",
        // Override a user's preference to send slash commands literally to the model.
        "--settings", #"{"disableSlashCommands":false}"#
    ]

    public func read(previous: ProviderUsage?) -> ProviderUsage {
        guard let executable = resolver(executableName, preferredPath, home) else {
            return unavailable(installed: false)
        }
        var usage = unavailable(installed: true)
        func run(_ arguments: [String]) -> ProcessResult {
            runner.run(executable: executable, arguments: arguments, currentDirectory: home)
        }
        func failed(_ message: String) -> ProviderUsage {
            usage.retainReading(from: previous, message: message)
            return usage
        }

        let help = run(["--help"])
        // Go's flag help is written to stderr even on a successful exit.
        let helpText = help.standardOutput + help.standardError
        guard help.succeeded, helpText.contains("--settings"),
              helpText.contains("--print-timeout"), helpText.contains("changelog") else {
            return failed("Update Antigravity with agy update in Terminal to enable safe allowance checks.")
        }
        let changelog = run(["changelog"])
        guard changelog.succeeded, Self.supportsUsageCommand(changelog.standardOutput) else {
            return failed("This Antigravity version could not be verified. Run agy update in Terminal, then refresh.")
        }
        let result = run(Self.usageArguments)
        guard let data = result.standardOutput.data(using: .utf8),
              let payload = (try? JSONSerialization.jsonObject(with: data)) as? [String: Any],
              result.succeeded, payload["status"] as? String == "SUCCESS" else {
            // Never display raw CLI output: errors may contain account details or credentials.
            let error = (result.standardOutput + result.standardError).lowercased()
            if error.contains("api key") || error.contains("gemini_api_key") {
                usage.condition = .unsupported
                usage.message = "API-key usage has no Google AI subscription allowance."
                return usage
            }
            if error.contains("authentication required") || error.contains("not authenticated") ||
                error.contains("not logged in") || error.contains("no stored credentials") {
                return usage
            }
            return failed("Could not refresh Antigravity usage. Open agy in Terminal to check your account, then refresh.")
        }
        guard payload["conversation_id"] as? String == "", finiteNumber(payload["num_turns"]) == 0,
              let tokens = payload["usage"] as? [String: Any], finiteNumber(tokens["total_tokens"]) == 0,
              let command = payload["command"] as? [String: Any], command["name"] as? String == "usage",
              let quota = command["data"] as? [String: Any],
              let reading = AntigravityQuotas.parse(quota) else {
            return failed("Antigravity returned an unrecognized quota response. Update agy, then refresh.")
        }
        usage.authenticated = true
        usage.windows = reading.windows
        usage.notes = reading.notes
        usage.blockedScopes = reading.blockedScopes
        usage.updatedAt = Date()
        usage.condition = .ready
        usage.message = reading.windows.isEmpty ? "No measurable allowance windows were reported by Antigravity." : ""
        return usage
    }

    /// `changelog` is local and does not authenticate. Version 1.1.11 introduced
    /// read-only /usage; require 1.1.12 or newer as our supported baseline.
    static func supportsUsageCommand(_ changelog: String) -> Bool {
        guard let first = changelog.split(whereSeparator: \.isNewline).first,
              first.hasSuffix(":"),
              first.dropLast().range(of: #"^\d+\.\d+\.\d+$"#, options: .regularExpression) != nil else { return false }
        let version = first.dropLast().split(separator: ".").compactMap { Int($0) }
        guard version.count == 3 else { return false }
        return !version.lexicographicallyPrecedes([1, 1, 12])
    }
}

public enum AntigravityQuotas {
    public struct Reading: Equatable, Sendable {
        public var windows: [UsageWindow]
        public var notes: [String]
        public var blockedScopes: [String]
    }

    public static func parse(_ payload: [String: Any]) -> Reading? {
        guard let groups = payload["groups"] as? [[String: Any]] else { return nil }
        var reading = Reading(windows: [], notes: [], blockedScopes: [])
        var seenBuckets = Set<String>()
        var seenLabels = Set<String>()
        for group in groups {
            guard let name = group["name"] as? String, !name.isEmpty,
                  let buckets = group["buckets"] as? [[String: Any]], !buckets.isEmpty else { return nil }
            let ids = buckets.compactMap { $0["id"] as? String }
            guard ids.count == buckets.count, ids.allSatisfy({ !$0.isEmpty }),
                  Set(ids).count == ids.count, Set(ids).isDisjoint(with: seenBuckets) else { return nil }
            seenBuckets.formUnion(ids)
            let scope = ids.sorted().joined(separator: "|")
            let title = String(name.prefix(40))
            // Every bucket constrains its group. A missing/disabled constraint must not
            // leave the other buckets looking usable in the menu bar.
            var windows: [UsageWindow] = []
            var unavailable = false
            for bucket in buckets {
                if bucket["disabled"] as? Bool == true { unavailable = true; continue }
                guard let fraction = finiteNumber(bucket["remaining_fraction"]), (0...1).contains(fraction) else {
                    unavailable = true
                    continue
                }
                let duration: Double?
                let windowName: String
                switch bucket["window"] as? String {
                case "5h": windowName = "5-hour"; duration = 300
                case "weekly": windowName = "Weekly"; duration = 10080
                default: windowName = String((bucket["name"] as? String ?? "Allowance").prefix(30)); duration = nil
                }
                var label = "\(title) · \(windowName)"
                if !seenLabels.insert(label).inserted {
                    label = String((bucket["id"] as! String).prefix(80))
                    guard seenLabels.insert(label).inserted else { return nil }
                }
                let reset = resetDate(bucket["reset_time"])
                if bucket["reset_time"] != nil && reset == nil { unavailable = true; continue }
                windows.append(UsageWindow(label: label, remainingPercent: fraction * 100,
                    resetsAt: reset, scopeID: scope, durationMinutes: duration))
            }
            if unavailable {
                reading.notes.append("\(title): allowance unavailable or disabled")
                reading.blockedScopes.append(scope)
            } else {
                reading.windows.append(contentsOf: windows)
            }
        }
        return reading
    }
}
