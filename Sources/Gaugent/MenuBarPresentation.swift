import Foundation
import GaugentCore

/// Only values actually rendered in the menu bar participate in change detection.
struct MenuBarPresentation: Equatable {
    let remainingFraction: Double?
    let title: String
    let alpha: Double
    let toolTip: String
    let accessibilityLabel: String

    init(overview: UsageOverview, hasEnabledProviders: Bool, displayMode: MenuBarDisplayMode,
         dimWhenIdle: Bool, shortcutRegistered: Bool) {
        let blocked = overview.blockedProvider
        let lowest = overview.lowest
        let remaining = lowest?.window.remainingPercent
        remainingFraction = remaining.map { $0 / 100 }
        let headline: String
        if let blocked { headline = "\(blocked.name) · limit reached" }
        else if let lowest { headline = "\(lowest.provider.name) · \(lowest.window.label)" }
        else { headline = hasEnabledProviders ? "Allowance unavailable" : "No tools enabled" }
        title = blocked != nil ? " !" : displayMode == .glyphAndPercent ? remaining.map { " \(Int($0.rounded(.down)))%" } ?? "" : ""
        alpha = dimWhenIdle && remaining == nil && blocked == nil ? 0.58 : 1
        toolTip = headline + " · " + overview.statusText + "\n" + (shortcutRegistered
            ? "gaugent — \(GlobalShortcutDefinition.showGaugent.label)" : "gaugent")
        accessibilityLabel = blocked.map { "gaugent, \($0.name), limit reached" } ?? remaining.map {
            "gaugent, lowest allowance \(Int($0)) percent remaining. \(headline). \(overview.statusText)"
        } ?? "gaugent, no usage readings"
    }
}

extension AppModel {
    var menuBarPresentation: MenuBarPresentation {
        MenuBarPresentation(overview: overview, hasEnabledProviders: !enabledProviders.isEmpty,
            displayMode: menuBarDisplayMode, dimWhenIdle: dimIconWhenIdle,
            shortcutRegistered: isGlobalShortcutRegistered)
    }
}
