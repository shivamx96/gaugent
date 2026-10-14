import Foundation

/// A tool whose subscription allowance gaugent can read without credentials or inference.
///
/// Providers run off the main thread and may block for a few seconds. They must never start
/// a conversation, run a tool, trigger a login, or read a token; the agent's own CLI stays
/// in charge of its credentials.
public protocol UsageProvider: Sendable {
    var id: String { get }
    var name: String { get }
    /// Command the user is expected to have on PATH, shown in Settings when it is missing.
    var executableName: String { get }
    /// Command the user can run to sign in when the provider reports `signedOut`.
    var signInCommand: String { get }
    func read(previous: ProviderUsage?) -> ProviderUsage
}

public extension UsageProvider {
    func unavailable(installed: Bool) -> ProviderUsage {
        ProviderUsage(
            id: id,
            name: name,
            installed: installed,
            condition: installed ? .signedOut : .notInstalled,
            message: installed ? "Sign in with the \(executableName) command to see usage." : "\(name) was not found on this Mac."
        )
    }
}

public struct UsageCollector: Sendable {
    public let providers: [any UsageProvider]

    public init(providers: [any UsageProvider]) {
        self.providers = providers
    }

    public static var standard: UsageCollector {
        UsageCollector(providers: [ClaudeProvider(), CodexProvider()])
    }

    /// Reads every enabled provider concurrently and keeps their configured order.
    public func collect(previous: UsageSnapshot?, enabled: Set<String>? = nil, now: Date = Date()) async -> UsageSnapshot {
        let selected = providers.filter { enabled?.contains($0.id) ?? true }
        let readings = await withTaskGroup(of: (Int, ProviderUsage).self) { group in
            for (index, provider) in selected.enumerated() {
                let last = previous?.provider(provider.id)
                group.addTask {
                    await Task.detached(priority: .utility) {
                        (index, provider.read(previous: last))
                    }.value
                }
            }
            var collected: [(Int, ProviderUsage)] = []
            for await reading in group { collected.append(reading) }
            return collected.sorted { $0.0 < $1.0 }.map(\.1)
        }
        return UsageSnapshot(checkedAt: now, providers: readings)
    }
}

public enum UsageCache {
    public static func load(from url: URL) -> UsageSnapshot? {
        guard let data = try? Data(contentsOf: url),
              let snapshot = try? decoder.decode(UsageSnapshot.self, from: data),
              snapshot.version == UsageSnapshot.currentVersion else { return nil }
        return snapshot
    }

    /// Writes atomically with owner-only permissions; the file holds quota numbers and hashed identities only.
    public static func save(_ snapshot: UsageSnapshot, to url: URL) {
        guard let data = try? encoder.encode(snapshot) else { return }
        let directory = url.deletingLastPathComponent()
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let temporary = directory.appendingPathComponent(".usage-\(UUID().uuidString)")
        guard FileManager.default.createFile(atPath: temporary.path, contents: data, attributes: [.posixPermissions: 0o600]) else { return }
        do {
            _ = try FileManager.default.replaceItemAt(url, withItemAt: temporary)
        } catch {
            try? FileManager.default.removeItem(at: temporary)
        }
    }

    private static var encoder: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .secondsSince1970
        encoder.outputFormatting = [.sortedKeys]
        return encoder
    }

    private static var decoder: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .secondsSince1970
        return decoder
    }
}
