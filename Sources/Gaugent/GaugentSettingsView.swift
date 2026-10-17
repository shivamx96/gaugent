import GaugentCore
import SwiftUI

struct GaugentSettingsView: View {
    @EnvironmentObject private var model: AppModel
    @Environment(\.colorScheme) private var colorScheme

    var body: some View {
        TabView {
            general.tabItem { Label("General", systemImage: "gearshape") }
            providers.tabItem { Label("Tools", systemImage: "terminal") }
            about.tabItem { Label("About", systemImage: "info.circle") }
        }
        .frame(width: 520, height: 420)
        .preferredColorScheme(model.appearance.colorScheme)
    }

    private var general: some View {
        Form {
            Section("Menu bar") {
                Picker("Show", selection: $model.menuBarDisplayMode) {
                    ForEach(MenuBarDisplayMode.allCases) { mode in Text(mode.title).tag(mode) }
                }
                Toggle("Dim the icon when no current readings are available", isOn: $model.dimIconWhenIdle)
                Picker("Appearance", selection: $model.appearance) {
                    ForEach(GaugentAppearance.allCases) { appearance in Text(appearance.title).tag(appearance) }
                }
            }
            Section("Refresh") {
                Toggle("Refresh every 5 minutes and when the panel opens", isOn: $model.refreshAutomatically)
                Stepper("Highlight allowances at or below \(model.lowThreshold)%", value: $model.lowThreshold, in: 5...50, step: 5)
                Text("This changes the visual highlight; it does not send notifications. Stale readings never trigger the highlight. A window older than ten minutes, or one whose reset time has passed, is shown dimmed until the tool reports again.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
            Section("System") {
                Toggle("Launch at login", isOn: Binding(
                    get: { model.isLaunchAtLoginEnabled },
                    set: { model.setLaunchAtLogin($0) }
                ))
                if let message = model.loginMessage {
                    Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                }
                LabeledContent("Global shortcut") {
                    Text(model.isGlobalShortcutRegistered ? GlobalShortcutDefinition.showGaugent.label : "Unavailable (in use by another app)")
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }

    private var providers: some View {
        Form {
            Section {
                ForEach(model.collector.providers, id: \.id) { provider in
                    let reading = model.snapshot?.provider(provider.id)
                    let path = ExecutableLocator.locate(provider.executableName)
                    Toggle(isOn: Binding(
                        get: { model.enabledProviders.contains(provider.id) },
                        set: { model.setProvider(provider.id, enabled: $0) }
                    )) {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(provider.name)
                            Text(path ?? "\(provider.executableName) not found on PATH or in common install folders")
                                .font(.system(size: 10.5, design: .monospaced))
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                                .truncationMode(.middle)
                            if let reading {
                                Text(model.enabledProviders.contains(provider.id) ? reading.connectionStatus : "Disabled")
                                    .font(.system(size: 10.5))
                                    .foregroundStyle(.secondary)
                            } else {
                                Text(model.enabledProviders.contains(provider.id) ? "Not checked yet" : "Disabled")
                                    .font(.system(size: 10.5)).foregroundStyle(.secondary)
                            }
                        }
                    }
                }
            } header: {
                Text("Tools")
            } footer: {
                Text("Enable the tools you want to track. Install and sign in to their CLIs to read subscription allowances. API-key accounts may not report subscription usage.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.secondary)
            }
        }
        .formStyle(.grouped)
    }

    private var about: some View {
        VStack(spacing: 14) {
            BrandMark(size: 56)
            Text("gaugent").font(.system(size: 16, weight: .semibold))
            Text(model.applicationVersion).font(.system(size: 11)).foregroundStyle(.secondary)
            Text("Subscription allowance for your coding agents, one glance away.")
                .font(.system(size: 11.5))
                .foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 320)
            HStack(spacing: 8) {
                Button("Copy Diagnostics") { model.copyDiagnostics() }.buttonStyle(QuietButtonStyle())
                Button("Reset Saved Readings") { model.clearCache() }.buttonStyle(QuietButtonStyle())
                Button("GitHub") { model.open(URL(string: "https://github.com/shivamx96/gaugent")!) }.buttonStyle(QuietButtonStyle())
            }
            .padding(.top, 4)
            if let message = model.actionMessage {
                Text(message).font(.system(size: 11)).foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }
            Text("Read from your tools’ own sessions. No prompts are sent and no tokens are stored. Saved readings contain quota data and hashed account identities.")
                .font(.system(size: 11)).foregroundStyle(.secondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 380)
            Spacer()
        }
        .padding(.horizontal, 20)
        .padding(.top, 24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
