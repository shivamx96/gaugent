import GaugentCore
import SwiftUI

struct ProviderCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let provider: ProviderUsage

    private var stale: Bool { model.isStale(provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(provider.name)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(provider.installed ? provider.planLabel : "Not installed")
                    .font(.system(size: 10, weight: .medium))
                    .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                    .padding(.horizontal, 6)
                    .frame(height: 17)
                    .background(GaugentTheme.surfaceSunk(colorScheme), in: RoundedRectangle(cornerRadius: 4, style: .continuous))
            }

            switch provider.condition {
            case .signedOut:
                guidance(
                    provider.message,
                    actionTitle: "Copy sign-in command & open Terminal",
                    action: { model.copyAndOpenTerminal(signInCommand) }
                )
            case .unsupported:
                guidance(provider.message + " Use a subscription account in the CLI, then refresh.", actionTitle: "Sign in with another account", action: { model.copyAndOpenTerminal(signInCommand) })
            case .notInstalled:
                guidance(provider.message, actionTitle: "Installation guide", action: {
                    model.open(URL(string: provider.id == "codex" ? "https://github.com/openai/codex#installation--setup" : "https://github.com/anthropics/claude-code#installation")!)
                })
            case .ready, .error:
                windows
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GaugentTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(GaugentTheme.hairline(colorScheme), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(provider.name), \(provider.connectionStatus)")
    }

    private var signInCommand: String {
        model.collector.providers.first { $0.id == provider.id }?.signInCommand ?? ""
    }

    @ViewBuilder
    private var windows: some View {
        if provider.windows.isEmpty {
            guidance(
                provider.message.isEmpty ? "No allowance windows were reported. Refresh or check your account in the CLI." : provider.message,
                actionTitle: provider.condition == .ready ? "Refresh" : nil,
                action: { Task { await model.refresh(reason: .user) } }
            )
        } else {
            VStack(alignment: .leading, spacing: 7) {
                ForEach(provider.windows) { window in
                    WindowRow(window: window, stale: stale)
                }
            }
            if !provider.notes.isEmpty {
                Text(provider.notes.joined(separator: " · "))
                    .font(.system(size: 11))
                    .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !provider.message.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: provider.condition == .error || provider.limitReached == true ? "exclamationmark.triangle" : "info.circle")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(provider.condition == .error || provider.limitReached == true ? GaugentTheme.warning(colorScheme) : GaugentTheme.tertiaryInk(colorScheme))
                        .padding(.top, 1)
                    Text(provider.message)
                        .font(.system(size: 11))
                        .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
        if !model.ageText(provider).isEmpty || provider.condition == .error {
            HStack {
                Text(model.ageText(provider))
                    .font(.system(size: 10.5))
                    .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
                Spacer()
                if provider.condition == .error || stale {
                    Button("Retry") { Task { await model.refresh(reason: .user) } }
                        .buttonStyle(QuietButtonStyle())
                        .disabled(model.isRefreshing)
                }
            }
        }
        if let next = model.nextAttemptText(provider) {
            Text(next)
                .font(.system(size: 10.5))
                .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
        } else if !model.refreshAutomatically && (provider.condition == .error || stale) {
            Text("Automatic refresh is off · ⌘R to retry")
                .font(.system(size: 10.5))
                .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
        }
    }

    private func guidance(_ message: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                VStack(alignment: .leading, spacing: 4) {
                    Button(actionTitle, action: action).buttonStyle(QuietButtonStyle())
                    if provider.condition == .signedOut || provider.condition == .unsupported, !signInCommand.isEmpty {
                        Text("Paste in Terminal and press Return:\n\(signInCommand)")
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
                    }
                }
            }
        }
    }
}

private struct WindowRow: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let window: UsageWindow
    let stale: Bool

    private var expired: Bool { model.isExpired(window) }
    private var uncertain: Bool { stale || expired }
    private var threshold: Double { Double(model.lowThreshold) }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline) {
                Text(window.label)
                    .font(.system(size: 10.5))
                    .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                    .lineLimit(1)
                Spacer()
                Text(valueText)
                    .font(.system(size: 10.5, weight: .semibold))
                    .monospacedDigit()
                    .foregroundStyle(valueColor)
            }
            HStack(spacing: 8) {
                GeometryReader { proxy in
                    ZStack(alignment: .leading) {
                        Capsule().fill(GaugentTheme.track(colorScheme))
                        if !expired {
                            Capsule()
                                .fill(GaugentTheme.level(window.remainingPercent, threshold: threshold, scheme: colorScheme))
                                .frame(width: max(0, proxy.size.width * window.remainingPercent / 100))
                                .opacity(stale ? 0.35 : 1)
                        }
                    }
                }
                .frame(height: 5)
                Text(model.resetText(window))
                    .font(.system(size: 10.5))
                    .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .layoutPriority(1)
            }

        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("\(window.label), \(valueText). \(model.resetText(window))")
    }

    private var valueText: String {
        if expired { return "Awaiting update" }
        return "\(Int(window.remainingPercent.rounded(.down)))% left" + (stale ? " · stale" : "")
    }

    private var valueColor: Color {
        if uncertain { return GaugentTheme.secondaryInk(colorScheme) }
        if window.remainingPercent <= 0 { return GaugentTheme.danger(colorScheme) }
        if window.remainingPercent <= threshold { return GaugentTheme.warning(colorScheme) }
        return GaugentTheme.primaryInk(colorScheme)
    }
}
