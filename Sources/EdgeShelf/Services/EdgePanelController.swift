import AppKit
import SwiftUI

final class ShelfPanel: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}

@MainActor
final class EdgePanelController {
    private let preferences: Preferences
    private let store: ShelfStore
    private let monitor: CopyShortcutMonitor
    private var panel: ShelfPanel!
    private var handle: NSPanel!
    private var timer: Timer?
    private var localEvents: Any?
    private var globalClicks: Any?
    private var currentScreen: NSScreen?
    private var edgeSince: TimeInterval?
    private var outsideSince: TimeInterval?
    private var edgeLatched = false
    private var layoutSignature = ""
    private var animationID = 0

    init(preferences: Preferences, store: ShelfStore, monitor: CopyShortcutMonitor) {
        self.preferences = preferences; self.store = store; self.monitor = monitor
    }

    func start() {
        panel = ShelfPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        panel.title = "拾边 · 临时收纳"
        panel.level = .floating
        panel.isFloatingPanel = true
        panel.hidesOnDeactivate = false
        panel.isReleasedWhenClosed = false
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        panel.contentView = NSHostingView(rootView: ContentView(store: store, preferences: preferences, monitor: monitor,
            collapse: { [weak self] in self?.hide(force: true) }))

        handle = NSPanel(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
        handle.level = .floating; handle.hidesOnDeactivate = false
        handle.isOpaque = false; handle.backgroundColor = .clear; handle.hasShadow = false
        handle.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary, .stationary]
        handle.contentView = NSHostingView(rootView: EdgeHandleView(action: { [weak self] in self?.toggle() }))
        localEvents = NSEvent.addLocalMonitorForEvents(matching: [.keyDown, .leftMouseDown, .rightMouseDown]) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown, event.keyCode == 53, self.panel.isKeyWindow, !self.store.isEditing {
                self.hide(force: true); return nil
            }
            return event
        }
        globalClicks = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            MainActor.assumeIsolated {
                guard let self, !self.panel.frame.contains(NSEvent.mouseLocation) else { return }
                self.hide()
            }
        }
        timer = Timer.scheduledTimer(withTimeInterval: 0.05, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.tick() }
        }
        tick()
        show(focus: true)
    }

    func toggle() { store.isExpanded ? hide(force: true) : show(focus: true) }

    func show(focus: Bool = false, screen: NSScreen? = nil) {
        guard panel != nil else { return }
        if store.isExpanded {
            if focus { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
            return
        }
        currentScreen = screen ?? preferredScreen()
        guard let screen = currentScreen else { return }
        let target = frame(for: screen)
        animationID += 1
        store.isExpanded = true
        outsideSince = nil
        handle.orderOut(nil)
        applyAppearance()
        panel.alphaValue = preferences.animation == .fade ? 0 : 1
        panel.setFrame(preferences.animation == .slide ? offscreen(target, screen: screen) : target, display: false)
        panel.orderFrontRegardless()
        NSAnimationContext.runAnimationGroup { context in
            context.duration = preferences.animation == .none ? 0 : 0.2
            context.timingFunction = CAMediaTimingFunction(name: .easeOut)
            panel.animator().setFrame(target, display: true)
            panel.animator().alphaValue = 1
        }
        if focus { NSApp.activate(ignoringOtherApps: true); panel.makeKeyAndOrderFront(nil) }
        if !store.isEditing { store.load() }
    }

    func hide(force: Bool = false) {
        guard store.isExpanded, force || (!store.keepExpanded && !store.isEditing && NSApp.modalWindow == nil) else { return }
        if !force, NSApp.isActive, let key = NSApp.keyWindow, key != panel { return }
        if force { store.keepExpanded = false }
        guard !store.isEditing else { return }
        store.isExpanded = false
        animationID += 1
        let token = animationID
        NSAnimationContext.runAnimationGroup { context in
            context.duration = preferences.animation == .none ? 0 : 0.18
            if preferences.animation == .slide, let screen = currentScreen {
                panel.animator().setFrame(offscreen(panel.frame, screen: screen), display: true)
            } else { panel.animator().alphaValue = 0 }
        } completionHandler: { [weak self] in
            Task { @MainActor in
                guard let self, self.animationID == token else { return }
                self.panel.orderOut(nil)
                self.updateHandle()
            }
        }
        outsideSince = nil
    }

    private func tick() {
        guard !NSScreen.screens.isEmpty else { return }
        let signature = "\(preferences.edge)-\(preferences.width)-\(preferences.heightRatio)-\(preferences.screenID)-\(preferences.appearance)-\(NSScreen.screens.map { $0.frame })"
        if layoutSignature != signature {
            layoutSignature = signature
            if let old = currentScreen, !NSScreen.screens.contains(where: { $0.shelfID == old.shelfID }) { currentScreen = nil }
            if preferences.screenID != "auto" { currentScreen = preferredScreen() }
            if store.isExpanded, let screen = currentScreen ?? preferredScreen() {
                currentScreen = screen
                panel.setFrame(frame(for: screen), display: true)
            }
            applyAppearance(); updateHandle()
        }
        let point = NSEvent.mouseLocation
        let now = ProcessInfo.processInfo.systemUptime
        let screen = store.isExpanded ? currentScreen : preferredScreen()
        guard let screen else { return }
        if !store.isExpanded, currentScreen?.shelfID != screen.shelfID {
            currentScreen = screen; updateHandle()
        }
        let touches = preferences.hoverEnabled && EdgeGeometry.touchesOuterEdge(point: point, screen: screen.frame,
            otherScreens: NSScreen.screens.filter { $0.shelfID != screen.shelfID }.map(\.frame),
            isLeft: preferences.edge == .left, exclusion: preferences.cornerExclusion)
        if touches {
            if !edgeLatched {
                if edgeSince == nil { edgeSince = now }
                if now - (edgeSince ?? now) >= preferences.revealDelay {
                    edgeLatched = true
                    if store.isExpanded && preferences.revealMode == .edgeToggle { hide(force: true) }
                    else if !store.isExpanded { show(screen: screen) }
                }
            }
        } else { edgeSince = nil; edgeLatched = false }
        guard store.isExpanded, preferences.revealMode == .autoHide else { return }
        if panel.frame.insetBy(dx: -8, dy: -8).contains(point) || store.keepExpanded || store.isEditing {
            outsideSince = nil
        } else {
            if outsideSince == nil { outsideSince = now }
            if now - (outsideSince ?? now) >= preferences.hideDelay { hide() }
        }
    }

    private func preferredScreen() -> NSScreen? {
        if preferences.screenID != "auto", let screen = NSScreen.screens.first(where: { $0.shelfID == preferences.screenID }) { return screen }
        return NSScreen.screens.first { $0.frame.contains(NSEvent.mouseLocation) } ?? NSScreen.main ?? NSScreen.screens.first
    }

    private func frame(for screen: NSScreen) -> NSRect {
        EdgeGeometry.panelFrame(visible: screen.visibleFrame, width: preferences.width,
                                heightRatio: preferences.heightRatio, isLeft: preferences.edge == .left)
    }

    private func offscreen(_ frame: NSRect, screen: NSScreen) -> NSRect {
        var result = frame
        result.origin.x = preferences.edge == .left ? screen.frame.minX - frame.width : screen.frame.maxX
        return result
    }

    private func updateHandle() {
        guard !store.isExpanded, let screen = currentScreen ?? preferredScreen() else { return }
        let x = preferences.edge == .left ? screen.frame.minX : screen.frame.maxX - 9
        handle.setFrame(NSRect(x: x, y: screen.visibleFrame.midY - 40, width: 9, height: 80), display: true)
        handle.orderFrontRegardless()
    }

    private func applyAppearance() {
        let name: NSAppearance.Name? = preferences.appearance == "light" ? .aqua : preferences.appearance == "dark" ? .darkAqua : nil
        panel.appearance = name.flatMap(NSAppearance.init(named:))
        handle.appearance = panel.appearance
    }

    func stop() {
        timer?.invalidate()
        if let localEvents { NSEvent.removeMonitor(localEvents) }
        if let globalClicks { NSEvent.removeMonitor(globalClicks) }
    }
}

extension NSScreen {
    var shelfID: String { (deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? NSNumber)?.stringValue ?? localizedName }
}

private struct EdgeHandleView: View {
    var action: () -> Void
    var body: some View {
        Button(action: action) {
            Capsule().fill(Color.accentColor.gradient).frame(width: 6, height: 60)
                .frame(width: 9, height: 80).contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("展开拾边 · Control ⇧ Space")
        .accessibilityLabel("展开拾边")
    }
}
