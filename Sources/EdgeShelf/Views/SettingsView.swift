import SwiftUI
import ServiceManagement

struct SettingsView: View {
    @ObservedObject var preferences: Preferences
    @ObservedObject var store: ShelfStore
    @ObservedObject var monitor: CopyShortcutMonitor
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var settingsError: String?

    var body: some View {
        TabView {
            captureSettings.tabItem { Label("快速收藏", systemImage: "keyboard") }
            dockSettings.tabItem { Label("边缘停靠", systemImage: "sidebar.right") }
            librarySettings.tabItem { Label("资料与通用", systemImage: "folder") }
        }
        .padding(20).frame(width: 560, height: 560)
        .alert("无法完成操作", isPresented: Binding(get: { settingsError != nil }, set: { if !$0 { settingsError = nil } })) {
            Button("好", role: .cancel) { settingsError = nil }
        } message: { Text(settingsError ?? "") }
    }

    private var captureSettings: some View {
        Form {
            Section {
                Toggle("连续复制快速收藏", isOn: $preferences.captureEnabled)
                Picker("连续按 C 的次数", selection: $preferences.copyCount) {
                    ForEach(2...5, id: \.self) { Text("\($0) 次").tag($0) }
                }
                slider("两次按键间隔", value: $preferences.copyInterval, range: 0.25...1.5, suffix: "秒")
                Text("按住 Command，连续按 \(preferences.copyCount) 次 C；也可以重复按 ⌘C。长按 C 不计数，其他按键会重置。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("把复制变成收藏") }
            Section {
                HStack {
                    Label(monitor.isMonitoring ? "连续复制识别已开启" : "连续复制识别未开启",
                          systemImage: monitor.isMonitoring ? "checkmark.shield.fill" : "shield.lefthalf.filled")
                        .foregroundStyle(monitor.isMonitoring ? .green : .secondary)
                    Spacer()
                    Button("请求权限") { monitor.requestPermission() }
                }
                Button("打开系统设置 → 输入监控") { monitor.openPermissionSettings() }
                Text("仅在达到设定的连续复制次数后读取剪贴板，不保存日常复制历史。授权后若未生效，请退出并重新打开应用。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("系统权限") }
            Section {
                Toggle("收藏后展开面板", isOn: $preferences.revealAfterCapture)
                Toggle("收藏成功提示音", isOn: $preferences.soundEnabled)
                LabeledContent("手动收藏剪贴板", value: "⇧ ⌘ V（面板内）")
                LabeledContent("全局展开 / 收起", value: "⌃ ⇧ Space")
            } header: { Text("收藏反馈") }
        }.formStyle(.grouped)
    }

    private var dockSettings: some View {
        Form {
            Section {
                Picker("停靠位置", selection: $preferences.edge) {
                    ForEach(DockEdge.allCases, id: \.self) { Text($0.title).tag($0) }
                }.pickerStyle(.segmented)
                Picker("显示器", selection: $preferences.screenID) {
                    Text("跟随鼠标所在显示器").tag("auto")
                    ForEach(NSScreen.screens, id: \.shelfID) { Text($0.localizedName).tag($0.shelfID) }
                }
                slider("面板宽度", value: $preferences.width, range: 360...640, suffix: "pt", decimals: 0)
                HStack {
                    Text("面板高度")
                    Slider(value: $preferences.heightRatio, in: 0.5...1)
                    Text("\(Int(preferences.heightRatio * 100))%").monospacedDigit().frame(width: 48, alignment: .trailing)
                }
                Picker("展开动画", selection: $preferences.animation) {
                    ForEach(PanelAnimation.allCases, id: \.self) { Text($0.title).tag($0) }
                }
            } header: { Text("面板外观") }
            Section {
                Toggle("鼠标触碰边缘展开", isOn: $preferences.hoverEnabled)
                Picker("收起方式", selection: $preferences.revealMode) {
                    ForEach(RevealMode.allCases, id: \.self) { Text($0.title).tag($0) }
                }
                slider("触边展开延迟", value: $preferences.revealDelay, range: 0...1.5, suffix: "秒")
                slider("离开收起延迟", value: $preferences.hideDelay, range: 0.2...3, suffix: "秒")
                slider("上下角排除区域", value: $preferences.cornerExclusion, range: 0...160, suffix: "pt", decimals: 0)
                Text("仅外侧屏幕边缘触发，穿过相邻显示器时不会误展开。点击 Pin 可保持展开，Esc 收起。面板支持所有桌面与全屏空间。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("触边与自动收起") }
        }.formStyle(.grouped)
    }

    private var librarySettings: some View {
        Form {
            Section {
                Text(preferences.libraryURL.path).font(.system(size: 11, design: .monospaced)).textSelection(.enabled)
                HStack {
                    Button("在 Finder 中打开") { NSWorkspace.shared.open(preferences.libraryURL) }
                    Button("打开其他资料库…") { chooseLibrary() }.disabled(store.isBusy)
                    Button("重新加载") { store.load() }.disabled(store.isBusy)
                }
                Text("JSON 保存索引、分类和待办状态；文本为 Markdown，图片为 PNG，文件保留原格式。收藏文件时保存独立副本。回收站中的内容保留在资料库中，可随时恢复。")
                    .font(.caption).foregroundStyle(.secondary)
                Text("切换资料库不会移动原资料。选择空文件夹可新建资料库；备份时复制整个资料库文件夹。文本文件的外部编辑会在重新展开面板时载入。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("开放的本地资料库") }
            Section {
                Picker("外观", selection: $preferences.appearance) {
                    Text("跟随系统").tag("system")
                    Text("浅色").tag("light")
                    Text("深色").tag("dark")
                }
                Toggle("登录时启动", isOn: $loginEnabled).onChange(of: loginEnabled) { _, enabled in
                    do {
                        if enabled { try SMAppService.mainApp.register() }
                        else { try SMAppService.mainApp.unregister() }
                        loginEnabled = SMAppService.mainApp.status == .enabled
                    } catch {
                        loginEnabled = SMAppService.mainApp.status == .enabled
                        settingsError = error.localizedDescription
                    }
                }
                Text("建议将应用放入「应用程序」后再开启登录启动与输入监控。")
                    .font(.caption).foregroundStyle(.secondary)
            } header: { Text("通用") }
            Section {
                LabeledContent("拾边 EdgeShelf", value: "1.0.0")
                Text("Swift + SwiftUI + AppKit。停靠交互参考 EdgeMark，专注临时数据收纳。")
                    .font(.caption).foregroundStyle(.secondary)
            }
        }.formStyle(.grouped)
    }

    private func slider(_ label: String, value: Binding<Double>, range: ClosedRange<Double>, suffix: String, decimals: Int = 2) -> some View {
        HStack {
            Text(label).frame(width: 108, alignment: .leading)
            Slider(value: value, in: range)
            Text("\(value.wrappedValue.formatted(.number.precision(.fractionLength(decimals)))) \(suffix)")
                .monospacedDigit().frame(width: 62, alignment: .trailing).foregroundStyle(.secondary)
        }
    }

    private func chooseLibrary() {
        let panel = NSOpenPanel()
        panel.title = "选择或新建资料库文件夹"
        panel.canChooseFiles = false; panel.canChooseDirectories = true
        panel.canCreateDirectories = true
        panel.prompt = "打开资料库"
        if panel.runModal() == .OK, let url = panel.url { store.switchLibrary(to: url) }
    }
}
