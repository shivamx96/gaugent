import GaugentCore
import SwiftUI

enum SettingsDestination: String, CaseIterable, Identifiable {
    case general = "General"
    case tools = "Tools"
    case advanced = "Advanced"

    var id: Self { self }
    var symbol: String {
        switch self {
        case .general: "slider.horizontal.3"
        case .tools: "terminal"
        case .advanced: "gearshape.2"
        }
    }
    var shortcut: KeyEquivalent {
        switch self {
        case .general: "1"
        case .tools: "2"
        case .advanced: "3"
        }
    }
}

struct GaugentSettingsView: View {
    static let size = CGSize(width: 660, height: 472)
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme
    @State private var destination: SettingsDestination

    init(initialDestination: SettingsDestination = .general) {
        _destination = State(initialValue: initialDestination)
    }

    var body: some View {
        HStack(spacing: 0) {
            sidebar
            Rectangle().fill(GaugentTheme.hairline(colorScheme)).frame(width: 0.5)
            VStack(alignment: .leading, spacing: 0) {
                Text(destination.rawValue)
                    .font(.system(size: 16, weight: .semibold))
                    .padding(.horizontal, 20)
                    .frame(height: 48, alignment: .leading)
                ScrollView {
                    VStack(spacing: 16) {
                        switch destination {
                        case .general: general
                        case .tools: providers
                        case .advanced: advanced
                        }
                        if let message = model.actionMessage, destination != .general {
                            Text(message)
                                .font(.system(size: 11))
                                .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .accessibilityLabel("Action result: \(message)")
                        }
                    }
                    .padding(.horizontal, 20)
                    .padding(.bottom, 20)
                    .id(destination)
                }
                .scrollIndicators(.automatic)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .frame(width: Self.size.width, height: Self.size.height)
        .background(GaugentTheme.surface(colorScheme))
        .tint(GaugentTheme.accent(colorScheme))
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var sidebar: some View {
        VStack(alignment: .leading, spacing: 2) {
            HStack(spacing: 8) {
                BrandMark(size: 22)
                Text("gaugent").font(.system(size: 13, weight: .semibold))
            }
            .padding(.horizontal, 12)
            .padding(.bottom, 14)

            ForEach(SettingsDestination.allCases) { item in
                Button { destination = item } label: {
                    HStack(spacing: 8) {
                        Image(systemName: item.symbol)
                            .font(.system(size: 11, weight: .medium))
                            .frame(width: 16)
                        Text(item.rawValue)
                            .font(.system(size: 11.5, weight: destination == item ? .semibold : .medium))
                        Spacer()
                    }
                    .foregroundStyle(destination == item ? GaugentTheme.primaryInk(colorScheme) : GaugentTheme.secondaryInk(colorScheme))
                    .padding(.horizontal, 9)
                    .frame(height: 28)
                    .background(destination == item ? GaugentTheme.selected(colorScheme) : .clear,
                                in: RoundedRectangle(cornerRadius: 6))
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .keyboardShortcut(item.shortcut, modifiers: .command)
                .accessibilityAddTraits(destination == item ? .isSelected : [])
            }
            Spacer()
            Text(model.applicationVersion)
                .font(.system(size: 10.5))
                .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
                .padding(.horizontal, 12)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.vertical, 14)
        .padding(.horizontal, 8)
        .frame(width: 154)
        .background(GaugentTheme.chrome(colorScheme))
    }

    private var general: some View {
        Group {
            SettingsGroup(title: "APPEARANCE") {
                SettingsRow(title: "Theme") {
                    Picker("Theme", selection: $model.appearance) {
                        ForEach(GaugentAppearance.allCases) { Text($0.title).tag($0) }
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 190)
                }
                SettingsRow(title: "Menu-bar icon") {
                    Picker("Menu-bar icon", selection: $model.menuBarDisplayMode) {
                        Text("Icon").tag(MenuBarDisplayMode.glyph)
                        Text("Icon + percent").tag(MenuBarDisplayMode.glyphAndPercent)
                    }
                    .labelsHidden().pickerStyle(.segmented).frame(width: 190)
                }
                SettingsRow(title: "Dim when idle", detail: "When no current readings are available") {
                    settingsToggle("Dim when idle", isOn: $model.dimIconWhenIdle)
                }
            }
            SettingsGroup(title: "BEHAVIOUR") {
                SettingsRow(title: "Launch at login", detail: model.loginMessage) {
                    settingsToggle("Launch at login", isOn: Binding(
                        get: { model.isLaunchAtLoginEnabled }, set: model.setLaunchAtLogin))
                }
                SettingsRow(title: "Refresh automatically", detail: "Every 5 minutes; on opening if older than a minute") {
                    settingsToggle("Refresh automatically", isOn: $model.refreshAutomatically)
                }
                SettingsRow(title: "Highlight low allowance", detail: "Visual highlight only; stale readings are excluded") {
                    Stepper("\(model.lowThreshold)%", value: $model.lowThreshold, in: 5...50, step: 5)
                        .font(.system(size: 11)).frame(width: 80)
                        .accessibilityLabel("Low allowance threshold")
                        .accessibilityValue("\(model.lowThreshold) percent")
                }
                SettingsRow(title: "Global shortcut", detail: model.isGlobalShortcutRegistered
                            ? "Open the panel from any app" : "Unavailable; another app may be using it") {
                    Text(GlobalShortcutDefinition.showGaugent.label)
                        .font(.system(size: 11, weight: .medium))
                        .padding(.horizontal, 8).frame(height: 22)
                        .background(GaugentTheme.surfaceSunk(colorScheme), in: RoundedRectangle(cornerRadius: 5))
                }
            }
            SettingsGroup(title: "UPDATES") {
                SettingsRow(title: "Current version") {
                    Text(GaugentVersion.string).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                SettingsRow(title: "Release downloads", detail: "Install new versions from GitHub Releases") {
                    Button("View releases") { model.open(URL(string: "https://github.com/shivamx96/gaugent/releases")!) }
                        .buttonStyle(QuietButtonStyle())
                }
            }
        }
    }

    private var providers: some View {
        Group {
            ForEach(model.collector.providers, id: \.id) { provider in
                let reading = model.snapshot?.provider(provider.id)
                let enabled = model.enabledProviders.contains(provider.id)
                let needsSignIn = reading?.authenticated != true || reading?.condition == .unsupported
                let path = ExecutableLocator.locate(provider.executableName)
                SettingsGroup(title: provider.name.uppercased()) {
                    SettingsRow(title: "Show allowance", detail: enabled ? "Included in the panel and menu-bar summary" : "This tool is hidden and will not be refreshed") {
                        settingsToggle("Show \(provider.name) allowance", isOn: Binding(
                            get: { model.enabledProviders.contains(provider.id) },
                            set: { model.setProvider(provider.id, enabled: $0) }))
                    }
                    SettingsRow(title: "Account", detail: enabled ? reading?.connectionStatus ?? "Not checked yet" : "Disabled") {
                        if enabled && path != nil {
                            Button(needsSignIn ? "Sign in…" : "Refresh") {
                                if needsSignIn { model.copyAndOpenTerminal(provider.signInCommand) }
                                else { Task { await model.refresh(reason: .user) } }
                            }
                            .buttonStyle(QuietButtonStyle())
                            .disabled(model.isRefreshing)
                        }
                    }
                    SettingsRow(title: "Executable", detail: path ?? "Not found on this Mac") {
                        if path == nil {
                            Button("Install…") { model.openInstallationGuide(for: provider.id) }
                                .buttonStyle(QuietButtonStyle())
                        }
                    }
                    if let reading, enabled, reading.updatedAt != nil {
                        SettingsRow(title: "Last reading", detail: model.nextAttemptText(reading)) {
                            Text(model.ageText(reading)).font(.system(size: 11)).foregroundStyle(.secondary)
                        }
                    }
                }
            }
            Text("Sign in with a subscription account in each tool’s CLI. Sign-in actions copy the command and open Terminal; paste it there, then refresh here.")
                .font(.system(size: 11))
                .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var advanced: some View {
        Group {
            SettingsGroup(title: "CACHE & DIAGNOSTICS") {
                SettingsRow(title: "Saved readings", detail: "Clear saved allowances and fetch new readings") {
                    Button("Reset") { model.clearCache() }.buttonStyle(QuietButtonStyle())
                }
                SettingsRow(title: "Diagnostics", detail: "Copy app and tool details without credentials") {
                    Button("Copy report") { model.copyDiagnostics() }.buttonStyle(QuietButtonStyle())
                }
                SettingsRow(title: "Refresh all data", detail: "Ask enabled tools for their latest allowances") {
                    Button(model.isRefreshing ? "Refreshing…" : "Refresh") { Task { await model.refresh(reason: .user) } }
                        .buttonStyle(QuietButtonStyle()).disabled(model.isRefreshing)
                }
            }
            SettingsGroup(title: "SUPPORT") {
                SettingsRow(title: "Report a problem", detail: "Include a diagnostics report to help investigate") {
                    Button("GitHub Issues") { model.open(URL(string: "https://github.com/shivamx96/gaugent/issues")!) }
                        .buttonStyle(QuietButtonStyle())
                }
                SettingsRow(title: "About gaugent", detail: "Subscription allowance, one glance away") {
                    Button("Project") { model.open(URL(string: "https://github.com/shivamx96/gaugent")!) }
                        .buttonStyle(QuietButtonStyle())
                }
            }
            SettingsGroup(title: "PRIVACY") {
                Text("Read from your tools’ own sessions. No prompts are sent and no tokens are stored. Saved readings contain quota data and hashed account identities. Resetting readings keeps your settings.")
                    .font(.system(size: 11))
                    .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(11)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
    }

    private func settingsToggle(_ title: String, isOn: Binding<Bool>) -> some View {
        Toggle(title, isOn: isOn).labelsHidden().toggleStyle(.switch).controlSize(.small)
    }
}

/// Shared settings rhythm follows Gitacre: section label, grouped rows, trailing controls.
struct SettingsGroup<Content: View>: View {
    let title: String
    @ViewBuilder let content: Content
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title).font(.system(size: 10, weight: .semibold)).tracking(0.65)
                .foregroundStyle(GaugentTheme.tertiaryInk(colorScheme))
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, 4)
            VStack(spacing: 0) { content }
                .background(GaugentTheme.chrome(colorScheme), in: RoundedRectangle(cornerRadius: 9))
                .overlay {
                    RoundedRectangle(cornerRadius: 9)
                        .strokeBorder(GaugentTheme.hairline(colorScheme), lineWidth: 0.5)
                }
        }
    }
}

struct SettingsRow<Trailing: View>: View {
    let title: String
    var detail: String? = nil
    @ViewBuilder let trailing: Trailing
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(title).font(.system(size: 11.5, weight: .medium))
                if let detail {
                    Text(detail).font(.system(size: 10.5))
                        .foregroundStyle(GaugentTheme.secondaryInk(colorScheme))
                        .fixedSize(horizontal: false, vertical: true)
                        .textSelection(.enabled)
                }
            }
            Spacer(minLength: 10)
            trailing.fixedSize()
        }
        .padding(.horizontal, 11)
        .padding(.vertical, 8)
        .frame(minHeight: detail == nil ? 36 : 43)
        .overlay(alignment: .bottom) {
            Rectangle().fill(GaugentTheme.separator(colorScheme)).frame(height: 0.5).padding(.leading, 11)
        }
    }
}
