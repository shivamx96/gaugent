import AppKit
import SwiftUI
import XCTest
import GaugentCore
@testable import Gaugent

/// Opt-in native renders, using fixtures only; never starts the user's CLIs.
final class PanelPreviewTests: XCTestCase {
    @MainActor
    func testRenderProductStates() async throws {
        guard let directory = ProcessInfo.processInfo.environment["GAUGENT_PREVIEW_DIR"] else {
            throw XCTSkip("Set GAUGENT_PREVIEW_DIR to render native product fixtures.")
        }
        let output = URL(fileURLWithPath: directory, isDirectory: true)
        try FileManager.default.createDirectory(at: output, withIntermediateDirectories: true)
        let now = Date()
        func ready(_ id: String, _ name: String, _ remaining: Double) -> ProviderUsage {
            ProviderUsage(id: id, name: name, installed: true, authenticated: true, plan: "pro",
                windows: [UsageWindow(label: "5-hour", remainingPercent: 72, resetsAt: now.addingTimeInterval(7200)),
                          UsageWindow(label: "7-day", remainingPercent: remaining, resetsAt: now.addingTimeInterval(180000))],
                updatedAt: now, condition: .ready, attemptedAt: now)
        }
        let claude = ready("claude", "Claude Code", 18)
        let codex = ready("codex", "Codex", 65)
        var stale = claude
        stale.condition = .error
        stale.message = "Could not refresh usage. Last reported readings are shown below."
        stale.updatedAt = now.addingTimeInterval(-1200)
        stale.failureStreak = 2
        var blocked = codex
        blocked.limitReached = true
        blocked.message = "Your account has reached a usage or spending limit."
        let missing = ProviderUsage(id: "claude", name: "Claude Code", message: "Claude Code was not found on this Mac.")
        let signedOut = ProviderUsage(id: "codex", name: "Codex", installed: true, condition: .signedOut,
                                      message: "Sign in to see your subscription allowance.")
        for (name, readings) in [("ready", [claude, codex]), ("stale", [stale, codex]),
                                 ("blocked", [claude, blocked]), ("setup", [missing, signedOut]), ("disabled", [])] {
            let suite = "gaugent-preview-\(UUID().uuidString)"
            let defaults = UserDefaults(suiteName: suite)!
            defer { defaults.removePersistentDomain(forName: suite) }
            defaults.set(readings.map(\.id), forKey: "enabledProviderIDs")
            let model = AppModel(collector: UsageCollector(providers: readings.map { FixtureProvider(reading: $0) }),
                                 defaults: defaults, storageURL: nil, startAutomatically: false)
            await model.refresh(reason: .user)
            for appearance in [GaugentAppearance.light, .dark] {
                model.appearance = appearance
                let view = GaugentPanel(onOpenSettings: {}, onQuit: {}).environmentObject(model)
                    .environment(\.colorScheme, appearance == .dark ? .dark : .light)
                let host = NSHostingView(rootView: view)
                let window = NSWindow(contentRect: NSRect(origin: .zero, size: GaugentAppDelegate.panelSize),
                                      styleMask: [.borderless], backing: .buffered, defer: false)
                window.isReleasedWhenClosed = false
                window.contentView = host
                window.appearance = NSAppearance(named: appearance == .dark ? .darkAqua : .aqua)
                host.frame = NSRect(origin: .zero, size: GaugentAppDelegate.panelSize)
                window.orderBack(nil)
                try await Task.sleep(for: .milliseconds(100))
                host.layoutSubtreeIfNeeded()
                host.displayIfNeeded()
                let bitmap = try XCTUnwrap(host.bitmapImageRepForCachingDisplay(in: host.bounds))
                host.cacheDisplay(in: host.bounds, to: bitmap)
                window.orderOut(nil)
                let png = try XCTUnwrap(bitmap.representation(using: .png, properties: [:]))
                try png.write(to: output.appendingPathComponent("\(name)-\(appearance.rawValue).png"))
            }
        }
    }
}

private struct FixtureProvider: UsageProvider {
    let reading: ProviderUsage
    var id: String { reading.id }
    var name: String { reading.name }
    var executableName: String { reading.id }
    var signInCommand: String { "\(reading.id) login" }
    func read(previous: ProviderUsage?) -> ProviderUsage { reading }
}
