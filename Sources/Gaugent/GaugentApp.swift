import AppKit
import Combine
import SwiftUI

extension Notification.Name {
    static let closeGaugentPanel = Notification.Name("closeGaugentPanel")
    static let openGaugentSettings = Notification.Name("openGaugentSettings")
}

@MainActor
final class GaugentAppDelegate: NSObject, NSApplicationDelegate, NSWindowDelegate {
    static let panelSize = NSSize(width: 360, height: 468)

    let model = AppModel()

    private var statusItem: NSStatusItem?
    private let popover = NSPopover()
    private var settingsWindow: NSWindow?
    private var globalShortcut: GlobalShortcutRegistrar?
    private var cancellables = Set<AnyCancellable>()

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.applicationIconImage = GaugentIconRenderer.applicationIcon()
        configurePopover()
        configureStatusItem()
        configureGlobalShortcut()
        observeModel()
        NotificationCenter.default.addObserver(self, selector: #selector(closePopover), name: .closeGaugentPanel, object: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(openSettingsFromNotification), name: .openGaugentSettings, object: nil)
    }

    func applicationWillTerminate(_ notification: Notification) {
        globalShortcut?.invalidate()
        NotificationCenter.default.removeObserver(self)
    }

    private func configurePopover() {
        popover.behavior = .transient
        popover.delegate = self
        popover.animates = false
        popover.contentSize = Self.panelSize
        popover.contentViewController = NSHostingController(
            rootView: GaugentPanel(
                onOpenSettings: { [weak self] in self?.showSettings() },
                onQuit: { NSApp.terminate(nil) }
            )
            .environmentObject(model)
        )
    }

    private func configureStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: [.leftMouseUp, .rightMouseUp])
        statusItem = item
        updateStatusItem()
    }

    private func observeModel() {
        model.objectWillChange
            .receive(on: RunLoop.main)
            .sink { [weak self] _ in DispatchQueue.main.async { self?.updateStatusItem() } }
            .store(in: &cancellables)

        model.$appearance
            .receive(on: RunLoop.main)
            .sink { [weak self] appearance in self?.applyAppearance(appearance) }
            .store(in: &cancellables)
    }

    private func applyAppearance(_ appearance: GaugentAppearance) {
        let appAppearance: NSAppearance? = switch appearance {
        case .system: nil
        case .light: NSAppearance(named: .aqua)
        case .dark: NSAppearance(named: .darkAqua)
        }
        popover.appearance = appAppearance
        settingsWindow?.appearance = appAppearance
    }

    private func configureGlobalShortcut() {
        globalShortcut = GlobalShortcutRegistrar(definition: .showGaugent) { [weak self] in self?.showPopover() }
        model.setGlobalShortcutRegistered(globalShortcut != nil)
        updateStatusItem()
    }

    @objc private func togglePopover() {
        if popover.isShown { closePopover() } else { showPopover() }
    }

    private func showPopover() {
        guard let button = statusItem?.button, !popover.isShown else { return }
        if NSApp.isActive {
            present(from: button)
            return
        }
        // A transient popover closes itself as soon as it notices the app is not active, which is
        // the case when a global hot key fires while another app is frontmost. Activation is
        // asynchronous, so wait for it (briefly) before presenting.
        var token: NSObjectProtocol?
        var presented = false
        let presentOnce = { [weak self] in
            guard !presented, let self else { return }
            presented = true
            if let token { NotificationCenter.default.removeObserver(token) }
            self.present(from: button)
        }
        token = NotificationCenter.default.addObserver(forName: NSApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in presentOnce() }
        NSApp.activate(ignoringOtherApps: true)
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { presentOnce() }
    }

    private func present(from button: NSStatusBarButton) {
        popover.show(relativeTo: button.bounds, of: button, preferredEdge: .minY)
        popover.contentViewController?.view.window?.makeKey()
        if model.refreshAutomatically { Task { await model.refresh(force: false) } }
    }

    @objc private func closePopover() { popover.performClose(nil) }

    private func showSettings() {
        closePopover()
        if settingsWindow == nil {
            let controller = NSHostingController(rootView: GaugentSettingsView().environmentObject(model))
            let window = NSWindow(
                contentRect: NSRect(x: 0, y: 0, width: 520, height: 420),
                styleMask: [.titled, .closable, .miniaturizable],
                backing: .buffered,
                defer: false
            )
            window.title = "gaugent Settings"
            window.titlebarSeparatorStyle = .line
            window.contentViewController = controller
            window.isReleasedWhenClosed = false
            window.center()
            window.delegate = self
            settingsWindow = window
            applyAppearance(model.appearance)
        }
        NSApp.activate(ignoringOtherApps: true)
        settingsWindow?.makeKeyAndOrderFront(nil)
    }

    @objc private func openSettingsFromNotification() { showSettings() }

    func windowWillClose(_ notification: Notification) { NSApp.hide(nil) }

    private func updateStatusItem() {
        guard let button = statusItem?.button else { return }
        let lowest = model.lowestRemaining
        button.image = GaugentIconRenderer.menuBarIcon(remaining: lowest.map { $0 / 100 })
        button.imagePosition = .imageLeft
        button.font = .monospacedDigitSystemFont(ofSize: 10.5, weight: .medium)
        button.title = model.menuBarDisplayMode == .glyphAndPercent && lowest != nil ? " \(Int(lowest!.rounded(.down)))%" : ""
        button.alphaValue = model.dimIconWhenIdle && lowest == nil ? 0.58 : 1
        button.toolTip = model.isGlobalShortcutRegistered
            ? "gaugent — \(GlobalShortcutDefinition.showGaugent.label)"
            : "gaugent"
        button.setAccessibilityLabel(lowest.map { "gaugent, lowest allowance \(Int($0)) percent remaining" } ?? "gaugent, no usage readings")
    }
}

extension GaugentAppDelegate: NSPopoverDelegate {
    func popoverDidClose(_ notification: Notification) {
        if settingsWindow?.isVisible != true { NSApp.hide(nil) }
    }
}

enum GaugentIconRenderer {
    /// Template dial whose needle tracks the lowest remaining share, or a bare dial when unknown.
    static func menuBarIcon(remaining: Double?) -> NSImage {
        let image = NSImage(size: NSSize(width: 18, height: 18), flipped: true) { rect in
            drawDial(in: rect.insetBy(dx: 1.5, dy: 1.5), color: .labelColor, lineWidth: 1.6, remaining: remaining)
            return true
        }
        image.isTemplate = true
        image.accessibilityDescription = "gaugent"
        return image
    }

    static func applicationIcon() -> NSImage {
        NSImage(size: NSSize(width: 512, height: 512), flipped: true) { rect in
            let tile = NSBezierPath(roundedRect: rect.insetBy(dx: 2, dy: 2), xRadius: 115, yRadius: 115)
            NSColor(red: 24 / 255, green: 124 / 255, blue: 118 / 255, alpha: 1).setFill()
            tile.fill()
            drawDial(in: rect.insetBy(dx: 110, dy: 110), color: .white, lineWidth: 30, remaining: 0.72)
            return true
        }
    }

    static func drawDial(in rect: NSRect, color: NSColor, lineWidth: CGFloat, remaining: Double?) {
        let geometry = GaugeGeometry(size: rect.size)
        let center = NSPoint(x: rect.minX + geometry.center.x, y: rect.minY + geometry.center.y)

        let arc = NSBezierPath()
        arc.lineWidth = lineWidth
        arc.lineCapStyle = .round
        // Flipped context: angles run clockwise, so 135° → 405° sweeps over the top.
        arc.appendArc(withCenter: center, radius: geometry.radius, startAngle: 135, endAngle: 405)
        color.setStroke()
        arc.stroke()

        if let remaining {
            let tip = geometry.needleTip(remaining: remaining)
            let needle = NSBezierPath()
            needle.lineWidth = lineWidth
            needle.lineCapStyle = .round
            needle.move(to: center)
            needle.line(to: NSPoint(x: rect.minX + tip.x, y: rect.minY + tip.y))
            needle.stroke()
        }
        let dot = max(1, lineWidth * 0.9)
        color.setFill()
        NSBezierPath(ovalIn: NSRect(x: center.x - dot, y: center.y - dot, width: dot * 2, height: dot * 2)).fill()
    }
}
