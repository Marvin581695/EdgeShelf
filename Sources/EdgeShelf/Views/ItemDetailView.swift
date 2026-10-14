import SwiftUI

struct ItemDetailView: View {
    @Environment(\.dismiss) private var dismiss
    @State var item: ClipItem
    @ObservedObject var store: ShelfStore

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Label(item.kind.title, systemImage: item.kind.symbol).font(.title3.bold())
                Spacer()
                Button("关闭") { dismiss() }.keyboardShortcut(.cancelAction)
            }
            TextField("标题", text: $item.title).font(.system(size: 16, weight: .semibold)).textFieldStyle(.roundedBorder)
            if item.kind == .text {
                TextEditor(text: $item.text).font(.system(size: 13, design: .monospaced))
                    .scrollContentBackground(.hidden).padding(8)
                    .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            } else if item.kind == .image, let image = NSImage(contentsOf: store.url(for: item)) {
                Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 16) {
                    Image(systemName: "doc.zipper").font(.system(size: 52)).foregroundStyle(.secondary)
                    Text(item.originalPath ?? item.title).font(.caption).textSelection(.enabled)
                    Button("打开文件") { NSWorkspace.shared.open(store.url(for: item)) }
                }.frame(maxWidth: .infinity, maxHeight: .infinity)
            }
            HStack {
                Toggle("Pin", isOn: $item.isPinned)
                Toggle("Todo", isOn: $item.isTodo).onChange(of: item.isTodo) { _, todo in if !todo { item.isDone = false } }
                if item.isTodo { Toggle("已完成", isOn: $item.isDone) }
                Spacer()
                Picker("分类", selection: $item.category) {
                    Text("未分类").tag(nil as String?)
                    ForEach(store.manifest.categories, id: \.self) { Text($0).tag(Optional($0)) }
                }.labelsHidden().frame(width: 110)
            }.font(.system(size: 11)).toggleStyle(.checkbox)
            Text("\(item.sourceApp ?? "手动收藏") · \(item.createdAt.formatted())")
                .font(.caption).foregroundStyle(.secondary)
            HStack {
                Button("在 Finder 中显示") { NSWorkspace.shared.activateFileViewerSelecting([store.url(for: item)]) }
                Spacer()
                Button("复制") { store.copy(item) }
                Button("保存") { store.save(item); dismiss() }.keyboardShortcut(.defaultAction)
                    .disabled(store.isBusy || item.title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }.padding(24).frame(width: 490, height: 540)
            .onAppear { store.isEditing = true }
    }
}

struct TextComposerView: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject var store: ShelfStore
    @State private var text = ""
    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            Text("随手记一点").font(.title3.bold())
            Text("支持纯文本和 Markdown，保存后可设为 Todo 或 Pin。")
                .font(.caption).foregroundStyle(.secondary)
            TextEditor(text: $text).font(.system(size: 13)).padding(8)
                .scrollContentBackground(.hidden).background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 8))
            HStack {
                Button("取消") { dismiss() }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("收藏") { store.capture(.text(text), source: "手动记录"); dismiss() }
                    .keyboardShortcut(.defaultAction)
                    .disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || store.isBusy)
            }
        }.padding(24).frame(width: 440, height: 360)
    }
}
