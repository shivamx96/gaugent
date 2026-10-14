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
        if let path = environment["PATH"] {
            candidates.append(contentsOf: path.split(separator: ":").map { "\($0)/\(name)" })
        }
        candidates.append(contentsOf: [
            "/opt/homebrew/bin/\(name)",
            "/usr/local/bin/\(name)",
            "/opt/local/bin/\(name)",
            home.appendingPathComponent(".local/bin/\(name)").path,
            home.appendingPathComponent(".npm-global/bin/\(name)").path,
            home.appendingPathComponent(".bun/bin/\(name)").path,
            home.appendingPathComponent(".volta/bin/\(name)").path,
            home.appendingPathComponent(".cargo/bin/\(name)").path
        ])
        return candidates.first { FileManager.default.isExecutableFile(atPath: $0) }
    }
}
