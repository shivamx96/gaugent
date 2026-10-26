import Foundation

/// Finds a CLI on the user's PATH or in the places package managers install it.
///
/// A menu-bar app launched from Finder inherits a short PATH, so the usual Homebrew,
/// npm, bun, and native-installer directories are always checked as well.
/// Resolves a command name, with an optional preferred path and the home directory to search under.
public typealias ExecutableResolver = @Sendable (_ name: String, _ preferredPath: String?, _ home: URL) -> String?

public enum ExecutableLocator {
    /// The default resolver, suitable for passing to a provider.
    public static let locate: ExecutableResolver = { name, preferredPath, home in
        locate(name, preferredPath: preferredPath, home: home)
    }

    public static func locate(
        _ name: String,
        preferredPath: String? = nil,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> String? {
        var candidates: [String] = []
        if let preferredPath, !preferredPath.isEmpty {
            candidates.append(preferredPath)
        }
        candidates.append(contentsOf: searchDirectories(environment: environment, home: home).map { "\($0)/\(name)" })
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }

    /// Finding an npm launcher is insufficient if its /usr/bin/env shebang cannot find node.
    /// Preserve inherited PATH precedence and all other environment values; add runtime locations.
    public static func childEnvironment(
        executable: String,
        environment: [String: String] = ProcessInfo.processInfo.environment,
        home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [String: String] {
        var result = environment
        let executableURL = URL(fileURLWithPath: executable)
        let directories = inheritedDirectories(environment) + [
            executableURL.deletingLastPathComponent().path,
            executableURL.resolvingSymlinksInPath().deletingLastPathComponent().path
        ] + fallbackDirectories(home: home)
        result["PATH"] = unique(directories).joined(separator: ":")
        return result
    }

    private static func searchDirectories(environment: [String: String], home: URL) -> [String] {
        unique(inheritedDirectories(environment) + fallbackDirectories(home: home))
    }

    private static func inheritedDirectories(_ environment: [String: String]) -> [String] {
        (environment["PATH"] ?? "").split(separator: ":").map(String.init)
    }

    private static func fallbackDirectories(home: URL) -> [String] {
        ["/opt/homebrew/bin", "/usr/local/bin", "/opt/local/bin"] +
        [".local/bin", ".npm-global/bin", ".bun/bin", ".volta/bin", ".cargo/bin"].map {
            home.appendingPathComponent($0).path
        } + ["/usr/bin", "/bin", "/usr/sbin", "/sbin"]
    }

    private static func unique(_ paths: [String]) -> [String] {
        var seen = Set<String>()
        return paths.filter { seen.insert($0).inserted }
    }
}
