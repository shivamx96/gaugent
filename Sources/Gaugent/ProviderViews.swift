import GaugentCore
import SwiftUI

struct ProviderCard: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    let provider: ProviderUsage

    private var stale: Bool { model.isStale(provider) }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .firstTextBaseline, spacing: 6) {
                Text(provider.name)
                    .font(.system(size: 12.5, weight: .semibold))
                Spacer()
                Text(provider.planLabel)
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
                    actionTitle: "Open Terminal",
                    action: { model.copyAndOpenTerminal(signInCommand) }
                )
            case .unsupported:
                guidance(provider.message, actionTitle: nil, action: nil)
            case .notInstalled:
                guidance(provider.message, actionTitle: nil, action: nil)
            case .ready, .error:
                windows
            }
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(GaugentTheme.card(colorScheme), in: RoundedRectangle(cornerRadius: 8, style: .continuous))
        .overlay {
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .strokeBorder(GaugentTheme.hairline(colorScheme), lineWidth: 0.5)
        }
        .accessibilityElement(children: .contain)
        .accessibilityLabel(accessibilityLabel)
    }

    private var signInCommand: String {
        model.collector.providers.first { $0.id == provider.id }?.signInCommand ?? ""
    }

    @ViewBuilder
    private var windows: some View {
        if provider.windows.isEmpty {
            guidance(
                provider.message.isEmpty ? "No allowance windows were reported." : provider.message,
                actionTitle: provider.condition == .error ? "Retry" : nil,
                action: { Task { await model.refresh(force: true) } }
            )
        } else {
            VStack(alignment: .leading, spacing: 9) {
                ForEach(provider.windows) { window in
                    WindowRow(window: window, stale: stale)
                }
            }
            if !provider.notes.isEmpty {
                Text(provider.notes.joined(separator: " · "))
                    .font(.system(size: 10))
                    .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
            }
            if !provider.message.isEmpty {
                HStack(alignment: .top, spacing: 5) {
                    Image(systemName: provider.condition == .error ? "exclamationmark.triangle" : "info.circle")
                        .font(.system(size: 9.5, weight: .medium))
                        .foregroundStyle(provider.condition == .error ? GaugentTheme.warning(colorScheme) : GaugentTheme.tertiaryInk(colorScheme))
                        .padding(.top, 1)
                    Text(provider.message)
                        .font(.system(size: 10))
                        .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            if !model.ageText(provider).isEmpty {
                Text(model.ageText(provider))
                    .font(.system(size: 9.5))
                    .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
            }
        }
    }

    private func guidance(_ message: String, actionTitle: String?, action: (() -> Void)?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(message)
                .font(.system(size: 10.5))
                .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                .fixedSize(horizontal: false, vertical: true)
            if let actionTitle, let action {
                HStack(spacing: 6) {
                    Button(actionTitle, action: action).buttonStyle(QuietButtonStyle())
                    if provider.condition == .signedOut, !signInCommand.isEmpty {
                        Text(signInCommand)
                            .font(.system(size: 10, design: .monospaced))
                            .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
                    }
                }
            }
        }
    }

    private var accessibilityLabel: String {
        let parts = provider.windows.map { "\($0.label) \(Int($0.remainingPercent)) percent left" }
        return "\(provider.name), \(provider.planLabel). " + (parts.isEmpty ? provider.message : parts.joined(separator: ", "))
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
                .font(.system(size: 9.5))
                .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
        }
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
