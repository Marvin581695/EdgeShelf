import AppKit
import ApplicationServices

/// A listen-only event tap never suppresses or synthesizes the user's copy events.
@MainActor
final class CopyShortcutMonitor: ObservableObject {
    @Published private(set) var hasPermission = false
    @Published private(set) var isMonitoring = false
    private let preferences: Preferences
    private let store: ShelfStore
    private var tap: CFMachPort?
    private var runLoopSource: CFRunLoopSource?
    private var timer: Timer?
    private var sequence = CopySequence()
    private var pendingCapture: DispatchWorkItem?
    private var captureGeneration = 0
    private var sequenceStartChange = 0
    private var lastCopyTime: TimeInterval = 0
    private var lastSourcePID: pid_t?

    init(preferences: Preferences, store: ShelfStore) {
        self.preferences = preferences; self.store = store
    }

    func start() {
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated { self?.refresh() }
        }
    }

    func requestPermission() {
        _ = CGRequestListenEventAccess()
        refresh()
    }

    func openPermissionSettings() {
        NSWorkspace.shared.open(URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent")!)
    }

    private func refresh() {
        hasPermission = CGPreflightListenEventAccess()
        if !hasPermission || !preferences.captureEnabled {
            stopTap(); return
        }
        if tap == nil { installTap() }
    }

    private func installTap() {
        let mask = CGEventMask(1 << CGEventType.keyDown.rawValue)
        let context = Unmanaged.passUnretained(self).toOpaque()
        tap = CGEvent.tapCreate(tap: .cgSessionEventTap, place: .headInsertEventTap,
            options: .listenOnly, eventsOfInterest: mask, callback: { _, type, event, context in
                guard let context else { return Unmanaged.passUnretained(event) }
                let monitor = Unmanaged<CopyShortcutMonitor>.fromOpaque(context).takeUnretainedValue()
                MainActor.assumeIsolated { monitor.handle(type: type, event: event) }
                return Unmanaged.passUnretained(event)
            }, userInfo: context)
        guard let tap else { isMonitoring = false; return }
        runLoopSource = CFMachPortCreateRunLoopSource(kCFAllocatorDefault, tap, 0)
        if let runLoopSource { CFRunLoopAddSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        CGEvent.tapEnable(tap: tap, enable: true)
        isMonitoring = true
    }

    private func handle(type: CGEventType, event: CGEvent) {
        if type == .tapDisabledByTimeout || type == .tapDisabledByUserInput {
            if let tap { CGEvent.tapEnable(tap: tap, enable: true) }
            sequence.reset(); return
        }
        guard preferences.captureEnabled, type == .keyDown else { return }
        let modifiers = event.flags.intersection([.maskCommand, .maskShift, .maskControl, .maskAlternate])
        let isCopy = event.getIntegerValueField(.keyboardEventKeycode) == 8 && modifiers == .maskCommand
        let now = ProcessInfo.processInfo.systemUptime
        let sourceApp = NSWorkspace.shared.frontmostApplication
        if lastSourcePID != sourceApp?.processIdentifier { sequence.reset() }
        if !sequence.hasPendingPresses || now - lastCopyTime > preferences.copyInterval {
            sequenceStartChange = NSPasteboard.general.changeCount
        }
        let triggered = sequence.press(isCommandC: isCopy,
            isRepeat: event.getIntegerValueField(.keyboardEventAutorepeat) != 0,
            time: now,
            required: preferences.copyCount, interval: preferences.copyInterval)
        if isCopy { lastCopyTime = now; lastSourcePID = sourceApp?.processIdentifier }
        guard triggered else { return }
        let source = sourceApp?.localizedName
        let previousChange = NSPasteboard.general.changeCount
        pendingCapture?.cancel()
        captureGeneration += 1
        waitForClipboard(previousChange: previousChange, sequenceStart: sequenceStartChange,
                         attempt: 0, source: source, generation: captureGeneration)
    }

    private func waitForClipboard(previousChange: Int, sequenceStart: Int, attempt: Int, source: String?, generation: Int) {
        let work = DispatchWorkItem { [weak self] in
            guard let self, generation == self.captureGeneration, self.preferences.captureEnabled else { return }
            // Allow the source app to finish its normal Cmd+C handler before taking a snapshot.
            if NSPasteboard.general.changeCount == previousChange && attempt < 7 {
                self.waitForClipboard(previousChange: previousChange, sequenceStart: sequenceStart, attempt: attempt + 1,
                                      source: source, generation: generation)
            } else if NSPasteboard.general.changeCount != previousChange || NSPasteboard.general.changeCount != sequenceStart {
                self.store.captureClipboard(source: source)
            } else {
                self.store.notice = "复制未更新剪贴板，可点击「收藏剪贴板」重试"
            }
        }
        pendingCapture = work
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.12, execute: work)
    }

    private func stopTap() {
        if let tap { CGEvent.tapEnable(tap: tap, enable: false); CFMachPortInvalidate(tap) }
        if let runLoopSource { CFRunLoopRemoveSource(CFRunLoopGetMain(), runLoopSource, .commonModes) }
        tap = nil; runLoopSource = nil; isMonitoring = false
        pendingCapture?.cancel(); captureGeneration += 1; sequence.reset()
    }

    func stop() { timer?.invalidate(); timer = nil; stopTap() }
}
