import SwiftUI
import UniformTypeIdentifiers

struct ContentView: View {
    @ObservedObject var store: ShelfStore
    @ObservedObject var preferences: Preferences
    @ObservedObject var monitor: CopyShortcutMonitor
    var collapse: () -> Void
    @State private var showComposer = false
    @State private var showCategory = false
    @State private var categoryName = ""
    @State private var editingItem: ClipItem?
    @State private var isDropTarget = false
    @FocusState private var searchFocused: Bool

    var body: some View {
        VStack(spacing: 0) {
            header
            searchBar
            filterBar
            Divider().padding(.top, 14)
            categoryBar
            if let error = store.errorMessage {
                errorBanner(error)
            } else if !monitor.isMonitoring && preferences.captureEnabled {
                permissionBanner
            }
            if store.items.isEmpty {
                emptyState
            } else {
                ScrollView {
                    LazyVStack(spacing: 12) {
                        ForEach(store.items) { item in
                            ClipCardView(item: item, store: store, open: { store.isEditing = true; editingItem = item })
                        }
                    }.padding(.horizontal, 20).padding(.top, 6).padding(.bottom, 20)
                }
            }
            footer
        }
        .background(.regularMaterial)
        .clipShape(RoundedRectangle(cornerRadius: 18, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(.primary.opacity(0.07)))
        .overlay(alignment: preferences.edge == .left ? .trailing : .leading) { resizeHandle }
        .overlay {
            if isDropTarget {
                RoundedRectangle(cornerRadius: 18).fill(Color.accentColor.opacity(0.12))
                    .overlay(RoundedRectangle(cornerRadius: 18).strokeBorder(Color.accentColor, style: StrokeStyle(lineWidth: 2, dash: [7])))
                    .overlay(Label("松开即可收藏", systemImage: "tray.and.arrow.down.fill").font(.title3.bold()).padding(20).background(.regularMaterial, in: Capsule()))
                    .allowsHitTesting(false)
            }
        }
        .onDrop(of: [UTType.fileURL, .utf8PlainText, .png, .tiff], isTargeted: $isDropTarget) { providers in
            DropService.receive(providers, store: store)
        }
        .sheet(isPresented: $showComposer, onDismiss: { store.isEditing = false }) {
            TextComposerView(store: store)
        }
        .sheet(item: $editingItem, onDismiss: { store.isEditing = false }) { item in
            ItemDetailView(item: item, store: store)
        }
        .sheet(isPresented: $showCategory, onDismiss: { store.isEditing = false }) {
            VStack(alignment: .leading, spacing: 18) {
                Text("新建分类").font(.title3.bold())
                TextField("例如：项目资料", text: $categoryName).textFieldStyle(.roundedBorder)
                    .onSubmit { createCategory() }
                HStack {
                    Button("取消") { showCategory = false }.keyboardShortcut(.cancelAction)
                    Spacer()
                    Button("创建") { createCategory() }.keyboardShortcut(.defaultAction)
                        .disabled(categoryName.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy)
                }
            }.padding(24).frame(width: 320)
        }
        .background {
            Group {
                Button("搜索") { searchFocused = true }.keyboardShortcut("f")
                Button("新建文本") { compose() }.keyboardShortcut("n")
                Button("收藏剪贴板") { store.captureClipboard() }.keyboardShortcut("v", modifiers: [.command, .shift])
                Button("保持展开") { store.keepExpanded.toggle() }.keyboardShortcut("p")
            }.hidden()
        }
    }

    private var header: some View {
        HStack(spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill").font(.system(size: 19, weight: .semibold))
                .foregroundStyle(.white).frame(width: 42, height: 42)
                .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 12))
            VStack(alignment: .leading, spacing: 3) {
                Text("拾边").font(.system(size: 22, weight: .bold, design: .rounded))
                Text("随手收纳，留待有用时。").font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            Button { store.keepExpanded.toggle() } label: {
                Image(systemName: store.keepExpanded ? "pin.fill" : "pin")
                    .foregroundStyle(store.keepExpanded ? Color.accentColor : .secondary)
            }.help("保持面板展开 · ⌘P")
            SettingsLink { Image(systemName: "slider.horizontal.3") }
                .simultaneousGesture(TapGesture().onEnded { NSApp.activate(ignoringOtherApps: true) })
                .help("设置")
            Button(action: collapse) { Image(systemName: preferences.edge == .right ? "sidebar.right" : "sidebar.left") }
                .help("收起面板 · Esc")
        }
        .buttonStyle(.plain)
        .font(.system(size: 14))
        .padding(.horizontal, 22).padding(.top, 24).padding(.bottom, 22)
    }

    private var searchBar: some View {
        HStack(spacing: 9) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("搜索文本、文件、来源…", text: $store.query)
                .textFieldStyle(.plain).focused($searchFocused)
            if store.query.isEmpty {
                Text("⌘ F").font(.system(size: 10, weight: .medium, design: .monospaced)).foregroundStyle(.tertiary)
            } else {
                Button { store.query = "" } label: { Image(systemName: "xmark.circle.fill").foregroundStyle(.secondary) }.buttonStyle(.plain)
            }
        }
        .font(.system(size: 12)).padding(11)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 20).padding(.bottom, 17)
    }

    private var filterBar: some View {
        HStack(spacing: 4) {
            ForEach(ShelfFilter.allCases) { filter in
                Button { store.filter = filter; store.selectedID = nil } label: {
                    HStack(spacing: 5) {
                        Image(systemName: filter.symbol)
                        Text(filter.title)
                        if filter == .todo && store.todoCount > 0 {
                            Text("\(store.todoCount)").font(.system(size: 10, weight: .bold))
                        }
                    }
                    .font(.system(size: 11, weight: store.filter == filter ? .semibold : .regular))
                    .frame(maxWidth: .infinity).padding(.vertical, 8)
                    .foregroundStyle(store.filter == filter ? Color.accentColor : .secondary)
                    .background(store.filter == filter ? Color.accentColor.opacity(0.1) : .clear, in: RoundedRectangle(cornerRadius: 7))
                }.buttonStyle(.plain)
            }
        }.padding(.horizontal, 20)
    }

    private var categoryBar: some View {
        HStack {
            Menu {
                Button("所有分类") { store.category = nil }
                Divider()
                ForEach(store.manifest.categories, id: \.self) { name in
                    Button(name) { store.category = name }
                }
                Divider()
                Button("新建分类…", systemImage: "folder.badge.plus") {
                    categoryName = ""; store.isEditing = true; showCategory = true
                }.disabled(!store.isReady || store.isBusy)
            } label: { Label(store.category ?? "所有分类", systemImage: "folder") }
                .menuStyle(.borderlessButton).fixedSize()
            Spacer()
            Menu {
                Button("所有类型") { store.kind = nil }
                ForEach(ClipKind.allCases, id: \.self) { kind in
                    Button(kind.title, systemImage: kind.symbol) { store.kind = kind }
                }
            } label: { Text(store.kind?.title ?? "所有类型") }
                .menuStyle(.borderlessButton).fixedSize()
            Text("\(store.items.count) 项").foregroundStyle(.tertiary)
        }
        .font(.system(size: 11)).foregroundStyle(.secondary)
        .padding(.horizontal, 22).padding(.vertical, 14)
    }

    private var permissionBanner: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "keyboard").foregroundStyle(Color.accentColor).padding(.top, 2)
            VStack(alignment: .leading, spacing: 4) {
                Text("开启连续复制收藏").font(.system(size: 12, weight: .semibold))
                Text("允许输入监控后，在任何应用连按 ⌘C 即可收藏。也可直接使用下方按钮。")
                    .font(.system(size: 11)).foregroundStyle(.secondary)
            }
            Button("开启") { monitor.requestPermission(); monitor.openPermissionSettings() }
                .font(.system(size: 11)).buttonStyle(.bordered)
        }
        .padding(12).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 20).padding(.bottom, 12)
    }

    private func errorBanner(_ message: String) -> some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.circle").foregroundStyle(.orange)
            VStack(alignment: .leading, spacing: 6) {
                Text(message).font(.system(size: 11)).textSelection(.enabled)
                if !store.isReady { Button("重新加载资料库") { store.load() }.buttonStyle(.link) }
            }
            Spacer(minLength: 0)
            Button { store.errorMessage = nil } label: { Image(systemName: "xmark") }.buttonStyle(.plain)
        }
        .padding(12).background(.orange.opacity(0.08), in: RoundedRectangle(cornerRadius: 9))
        .padding(.horizontal, 20).padding(.bottom, 10)
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            Spacer()
            Image(systemName: store.filter == .trash ? "trash" : "tray.and.arrow.down")
                .font(.system(size: 36, weight: .light)).foregroundStyle(Color.accentColor.opacity(0.65))
                .frame(width: 82, height: 82).background(Color.accentColor.opacity(0.06), in: RoundedRectangle(cornerRadius: 23))
            Text(emptyTitle).font(.system(size: 17, weight: .semibold))
            Text(store.query.isEmpty && store.activeCount == 0 && store.filter == .all
                 ? "值得留住的文字、图片、文件，\n都可以先放在这里。" : "换个分类或搜索词，\n也可以收藏一些新内容。")
                .font(.system(size: 12)).foregroundStyle(.secondary).multilineTextAlignment(.center).lineSpacing(5)
            if store.query.isEmpty && store.activeCount == 0 && store.filter == .all {
                HStack(spacing: 8) {
                    ForEach(0..<preferences.copyCount, id: \.self) { _ in
                        Text("⌘ C").font(.system(size: 13, weight: .medium, design: .monospaced))
                            .padding(.horizontal, 10).padding(.vertical, 7)
                            .background(.quaternary, in: RoundedRectangle(cornerRadius: 6))
                    }
                }.padding(.top, 2)
                Text("连续复制 \(preferences.copyCount) 次，轻松收藏").font(.system(size: 10)).foregroundStyle(.tertiary)
            }
            Spacer()
            Label("也支持将文件、图片或文本拖入面板", systemImage: "arrow.down.doc")
                .font(.system(size: 10)).foregroundStyle(.tertiary).padding(.bottom, 24)
        }.frame(maxWidth: .infinity)
    }

    private var emptyTitle: String {
        if !store.query.isEmpty { return "没有找到相关内容" }
        switch store.filter {
        case .all: return store.activeCount == 0 ? "给灵感一个临时落脚点" : "这个分类还很安静"
        case .pinned: return "常用的资料，置顶就好"
        case .todo: return "留给接下来要做的事"
        case .trash: return "回收站是空的"
        }
    }

    private var footer: some View {
        VStack(spacing: 12) {
            Divider()
            HStack(spacing: 10) {
                Button { store.captureClipboard() } label: {
                    Label("收藏剪贴板", systemImage: "plus").font(.system(size: 12, weight: .semibold))
                        .frame(maxWidth: .infinity).padding(.vertical, 9)
                }.buttonStyle(.plain).foregroundStyle(.white)
                    .background(Color.accentColor.gradient, in: RoundedRectangle(cornerRadius: 9))
                    .help("手动收藏当前剪贴板 · ⇧⌘V")
                Menu {
                    Button("新建文本…", systemImage: "square.and.pencil") { compose() }
                    Button("收藏文件…", systemImage: "folder.badge.plus") { store.chooseFiles() }
                    Button("打开资料库", systemImage: "arrow.up.forward.square") { NSWorkspace.shared.open(preferences.libraryURL) }
                } label: {
                    Image(systemName: "ellipsis").frame(width: 28, height: 32)
                }.menuStyle(.borderlessButton).fixedSize().help("更多收藏方式")
            }.disabled(store.isBusy || !store.isReady).padding(.horizontal, 20)
            HStack(spacing: 5) {
                if store.isBusy { ProgressView().controlSize(.mini) }
                else { Circle().fill(monitor.isMonitoring ? Color.green : Color.secondary.opacity(0.5)).frame(width: 5, height: 5) }
                Text(store.isBusy ? "正在保存…" : store.notice ?? (monitor.isMonitoring ? "连续复制 \(preferences.copyCount) 次即可收藏" : "本地收纳 · 随时可用"))
                    .lineLimit(1)
                Spacer(minLength: 4)
                Text("⌃ ⇧ Space").font(.system(size: 9, design: .monospaced)).foregroundStyle(.tertiary)
            }.font(.system(size: 10)).foregroundStyle(.secondary).padding(.horizontal, 22).padding(.bottom, 16)
        }
    }

    private var resizeHandle: some View {
        ResizeHandle(width: $preferences.width, isLeft: preferences.edge == .left)
            .frame(width: 5).padding(.vertical, 24)
    }

    private func compose() { store.isEditing = true; showComposer = true }
    private func createCategory() { store.addCategory(categoryName); showCategory = false }
}

private struct ResizeHandle: View {
    @Binding var width: Double
    var isLeft: Bool
    @State private var initialWidth: Double?
    var body: some View {
        Color.clear.contentShape(Rectangle())
            .onHover { hovering in hovering ? NSCursor.resizeLeftRight.push() : NSCursor.pop() }
            .gesture(DragGesture(minimumDistance: 1)
                .onChanged { value in
                    if initialWidth == nil { initialWidth = width }
                    width = min(640, max(360, (initialWidth ?? width) + value.translation.width * (isLeft ? 1 : -1)))
                }.onEnded { _ in initialWidth = nil })
            .help("拖动调整面板宽度")
    }
}
