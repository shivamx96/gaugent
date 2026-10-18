import AppKit
import GaugentCore
import SwiftUI

struct GaugentPanel: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let onOpenSettings: () -> Void
    let onQuit: () -> Void

    var body: some View {
        VStack(spacing: 0) {
            header
            summary
            content
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            UpdateBanner()
            footer
        }
        .frame(width: GaugentAppDelegate.panelSize.width, height: GaugentAppDelegate.panelSize.height)
        .background(GaugentTheme.surface(colorScheme))
        .tint(GaugentTheme.accent(colorScheme))
        .preferredColorScheme(model.appearance.colorScheme)
        .background(PanelKeyboardMonitor(handler: handleKeyboardAction))
    }

    private var header: some View {
        HStack(spacing: 8) {
            BrandMark(size: 19)
            VStack(alignment: .leading, spacing: 1) {
                Text("gaugent")
                    .font(.system(size: 12.5, weight: .semibold))
                    .tracking(-0.15)
                Text(subtitle)
                    .font(.system(size: 10.5))
                    .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
                    .lineLimit(1)
            }
            Spacer(minLength: 6)
            Button {
                Task { await model.refresh(reason: .user) }
            } label: {
                Image(systemName: "arrow.clockwise").opacity(model.isRefreshing ? 0.45 : 1)
            }
            .buttonStyle(QuietIconButtonStyle())
            .disabled(model.isRefreshing)
            .help("Refresh (⌘R)")
            .accessibilityLabel("Refresh")
        }
        .padding(.horizontal, 11)
        .frame(height: 44)
        .background(GaugentTheme.chrome(colorScheme))
        .overlay(alignment: .bottom) {
            Rectangle().fill(GaugentTheme.hairline(colorScheme)).frame(height: 0.5)
        }
    }

    private var subtitle: String {
        if model.isRefreshing { return "Checking tools…" }
        if !model.hasLoaded && model.snapshot == nil { return "Checking installed tools…" }
        guard let lastAttempt = model.visibleProviders.compactMap(\.attemptedAt).max() else { return "Subscription allowance" }
        let minutes = max(0, Int(model.now.timeIntervalSince(lastAttempt) / 60))
        return minutes < 1 ? "Checked just now" : "Checked \(minutes)m ago"
    }

    private var summaryDetail: String {
        if model.overview.blockedProvider != nil { return "Usage or spending is currently limited" }
        if model.lowestRemaining != nil { return "Lowest current allowance remaining" }
        return model.enabledProviders.isEmpty ? "Choose tools in Settings to get started" : "Check tool status below to continue"
    }

    private var summary: some View {
        HStack(alignment: .center, spacing: 8) {
            VStack(alignment: .leading, spacing: 2) {
                Text(model.headline)
                    .font(.system(size: 11.5, weight: .semibold))
                    .fixedSize(horizontal: false, vertical: true)
                Text(summaryDetail)
                    .font(.system(size: 10.5))
                    .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
            }
            Spacer(minLength: 4)
            Text(model.overview.blockedProvider != nil ? "Limited" : model.lowestRemaining.map { "\(Int($0.rounded(.down)))%" } ?? "—")
                .font(.system(size: 20, weight: .semibold, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(model.needsAttention ? GaugentTheme.warning(colorScheme) : GaugentTheme.primaryInk(colorScheme))
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 9)
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private var content: some View {
        if model.visibleProviders.isEmpty {
            if !model.hasLoaded {
                FirstReadView()
            } else {
                EmptyStateView(
                    symbol: "gauge.with.dots.needle.33percent",
                    title: model.enabledProviders.isEmpty ? "No tools enabled" : "Set up your tools",
                    message: "Enable Claude Code or Codex in Settings to see its subscription allowance.",
                    actionTitle: "Open Settings",
                    action: onOpenSettings
                )
            }
        } else {
            ScrollView {
                VStack(spacing: 6) {
                    ForEach(model.visibleProviders) { provider in
                        ProviderCard(provider: provider)
                    }
                    if let message = model.actionMessage {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(.horizontal, 2)
                    }
                }
                .padding(.horizontal, 10)
                .padding(.top, 0)
                .padding(.bottom, 8)
            }
            .scrollIndicators(.automatic)
        }
    }

    private var footer: some View {
        HStack(spacing: 6) {
            Circle().fill(statusColor).frame(width: 5, height: 5)
            Text(statusText)
                .font(.system(size: 11))
                .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                .lineLimit(1)
            Spacer()
            Button("Settings", action: onOpenSettings)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                .keyboardShortcut(",", modifiers: .command)
            Button("Quit", action: onQuit)
                .buttonStyle(.plain)
                .font(.system(size: 11))
                .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
        }
        .padding(.horizontal, 10)
        .frame(height: 30)
        .background(GaugentTheme.chrome(colorScheme))
        .overlay(alignment: .top) {
            Rectangle().fill(GaugentTheme.hairline(colorScheme)).frame(height: 0.5)
        }
    }

    private var statusText: String { model.overview.statusText }

    private var statusColor: Color {
        if model.visibleProviders.isEmpty { return GaugentTheme.tertiaryInk(colorScheme) }
        if model.needsAttention || model.overview.currentCount < model.visibleProviders.count {
            return GaugentTheme.warning(colorScheme)
        }
        return GaugentTheme.good(colorScheme)
    }

    private func handleKeyboardAction(_ action: PanelKeyboardAction) -> Bool {
        switch action {
        case .refresh: Task { await model.refresh(reason: .user) }
        case .escape: NotificationCenter.default.post(name: .closeGaugentPanel, object: nil)
        }
        return true
    }
}

enum PanelKeyboardAction {
    case refresh
    case escape
}

private struct PanelKeyboardMonitor: NSViewRepresentable {
    let handler: (PanelKeyboardAction) -> Bool

    func makeNSView(context: Context) -> PanelKeyboardView {
        let view = PanelKeyboardView()
        view.handler = handler
        return view
    }

    func updateNSView(_ nsView: PanelKeyboardView, context: Context) { nsView.handler = handler }
}

private final class PanelKeyboardView: NSView {
    var handler: ((PanelKeyboardAction) -> Bool)?
    private var monitor: Any?

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard self?.window === event.window, let action = Self.action(for: event), self?.handler?(action) == true else { return event }
            return nil
        }
    }

    private static func action(for event: NSEvent) -> PanelKeyboardAction? {
        let flags = event.modifierFlags.intersection(.deviceIndependentFlagsMask)
        if flags.contains(.command), event.charactersIgnoringModifiers?.lowercased() == "r" { return .refresh }
        if event.keyCode == 53 { return .escape }
        return nil
    }

    deinit { if let monitor { NSEvent.removeMonitor(monitor) } }
}

struct EmptyStateView: View {
    let symbol: String
    let title: String
    let message: String
    var actionTitle: String? = nil
    var action: (() -> Void)? = nil
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            ZStack {
                RoundedRectangle(cornerRadius: 9, style: .continuous)
                    .fill(GaugentTheme.surfaceSunk(colorScheme))
                Image(systemName: symbol)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
            }
            .frame(width: 34, height: 34)
            .padding(.bottom, 2)

            Text(title).font(.system(size: 12.5, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 250)

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(QuietButtonStyle())
                    .padding(.top, 3)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(24)
    }
}

private struct FirstReadView: View {
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(spacing: 8) {
            ForEach(0..<2, id: \.self) { _ in
                VStack(alignment: .leading, spacing: 10) {
                    RoundedRectangle(cornerRadius: 2).fill(GaugentTheme.surfaceSunk(colorScheme)).frame(width: 96, height: 9)
                    ForEach(0..<2, id: \.self) { _ in
                        VStack(alignment: .leading, spacing: 5) {
                            RoundedRectangle(cornerRadius: 2).fill(GaugentTheme.surfaceSunk(colorScheme).opacity(0.7)).frame(width: 150, height: 7)
                            RoundedRectangle(cornerRadius: 2.5).fill(GaugentTheme.surfaceSunk(colorScheme)).frame(height: 5)
                        }
                    }
                }
                .padding(12)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(GaugentTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
            }
            Text("Asking each installed CLI for its usage. This takes a few seconds the first time.")
                .font(.system(size: 10.5))
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 260)
                .padding(.top, 10)
            Spacer()
        }
        .padding(.horizontal, 10)
        .padding(.top, 10)
    }
}
