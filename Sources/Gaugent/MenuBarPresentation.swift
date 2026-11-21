import Foundation
import GaugentCore

/// Only values actually rendered in the menu bar participate in change detection.
struct MenuBarPresentation: Equatable {
    let providerID: String?
    let remainingFraction: Double?
    let title: String
    let alpha: Double
    let toolTip: String
    let accessibilityLabel: String

    init(overview: UsageOverview, hasEnabledProviders: Bool, displayMode: MenuBarDisplayMode,
         dimWhenIdle: Bool, shortcutRegistered: Bool) {
        let lowest = overview.lowestUsable
        let blocked = lowest == nil ? overview.blockedProvider : nil
        let remaining = lowest?.window.remainingPercent
        providerID = lowest?.provider.id ?? blocked?.id
        remainingFraction = remaining.map { $0 / 100 }
        // A positive fraction must not be presented as an exhausted allowance.
        let percent = remaining.map { $0 < 1 ? "<1%" : "\(Int($0.rounded(.down)))%" }
        let headline: String
        if let blocked { headline = "\(Self.providerLabel(blocked)) · limit reached" }
        else if let lowest, let percent {
            var detail = "\(Self.providerLabel(lowest.provider)) · \(lowest.window.label) · \(percent) remaining"
            if let reset = lowest.window.resetsAt {
                if reset.timeIntervalSince1970.isFinite, reset <= .distantFuture, reset >= .distantPast {
                    detail += " · resets \(reset.formatted(date: .abbreviated, time: .shortened))"
                } else {
                    detail += " · reset time unavailable"
                }
            }
            headline = detail
        }
        else { headline = hasEnabledProviders ? "Allowance unavailable" : "No tools enabled" }
        title = blocked != nil ? " !" : displayMode == .glyphAndPercent ? percent.map { " \($0)" } ?? "" : ""
        alpha = dimWhenIdle && remaining == nil && blocked == nil ? 0.58 : 1
        toolTip = headline + " · " + overview.statusText + "\n" + (shortcutRegistered
            ? "gaugent — \(GlobalShortcutDefinition.showGaugent.label)" : "gaugent")
        accessibilityLabel = blocked.map { "gaugent, \($0.name), limit reached" } ?? percent.map { _ in
            "gaugent, lowest usable allowance. \(headline.replacingOccurrences(of: "<1%", with: "less than 1 percent")). \(overview.statusText)"
        } ?? "gaugent, no usage readings"
    }

    private static func providerLabel(_ provider: ProviderUsage) -> String {
        switch provider.id {
        case "codex": return "OpenAI · \(provider.name)"
        case "claude": return "Anthropic · \(provider.name)"
        case "antigravity": return "Google · \(provider.name)"
        default: return provider.name
        }
    }
}

extension AppModel {
    var menuBarPresentation: MenuBarPresentation {
        MenuBarPresentation(overview: overview, hasEnabledProviders: !enabledProviders.isEmpty,
            displayMode: menuBarDisplayMode, dimWhenIdle: dimIconWhenIdle,
            shortcutRegistered: isGlobalShortcutRegistered)
    }
}
