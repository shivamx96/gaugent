import AppKit

// A plain AppKit entry point: a SwiftUI `App` would add a Settings scene that macOS can open
// on its own at launch, and a menu-bar-only app has no use for one.
MainActor.assumeIsolated {
    let application = NSApplication.shared
    let delegate = GaugentAppDelegate()
    application.delegate = delegate
    application.setActivationPolicy(.accessory)
    application.run()
}
