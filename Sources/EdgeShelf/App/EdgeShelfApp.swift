import SwiftUI

@main
struct EdgeShelfApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate
    private let runtime = AppRuntime.shared

    var body: some Scene {
        MenuBarExtra("拾边", systemImage: "tray.and.arrow.down.fill") {
            Button("展开 / 收起拾边    ⌃⇧Space") { runtime.panel.toggle() }
            Button("收藏当前剪贴板") { runtime.store.captureClipboard() }
            Button("收藏文件…") { runtime.panel.show(focus: true); runtime.store.chooseFiles() }
            Divider()
            Toggle("保持面板展开", isOn: Binding(get: { runtime.store.keepExpanded }, set: { runtime.store.keepExpanded = $0 }))
            SettingsLink { Text("设置…") }
            Button("打开资料库") { NSWorkspace.shared.open(runtime.preferences.libraryURL) }
            Divider()
            Button("退出拾边") { NSApp.terminate(nil) }.keyboardShortcut("q")
        }
        Settings {
            SettingsView(preferences: runtime.preferences, store: runtime.store, monitor: runtime.monitor)
        }
    }
}

@MainActor
final class AppRuntime {
    static let shared = AppRuntime()
    let preferences: Preferences
    let store: ShelfStore
    let monitor: CopyShortcutMonitor
    let panel: EdgePanelController
    private var hotKey: GlobalHotKey?

    private init() {
        let preferences = Preferences()
        let store = ShelfStore(preferences: preferences)
        let monitor = CopyShortcutMonitor(preferences: preferences, store: store)
        self.preferences = preferences; self.store = store; self.monitor = monitor
        panel = EdgePanelController(preferences: preferences, store: store, monitor: monitor)
        store.didCapture = { [weak self] in
            guard let self, self.preferences.revealAfterCapture else { return }
            self.panel.show()
        }
    }

    func start() {
        store.load()
        panel.start()
        monitor.start()
        hotKey = GlobalHotKey { [weak self] in self?.panel.toggle() }
    }

    func stop() { monitor.stop(); panel.stop() }
}

final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)
        AppRuntime.shared.start()
    }
    func applicationWillTerminate(_ notification: Notification) { AppRuntime.shared.stop() }
    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool { false }
}
