import SwiftUI

struct ClipCardView: View {
    let item: ClipItem
    @ObservedObject var store: ShelfStore
    var open: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 7) {
                Image(systemName: item.kind.symbol).foregroundStyle(kindColor)
                Text(item.kind.title).foregroundStyle(.secondary)
                if item.isPinned { Image(systemName: "pin.fill").foregroundStyle(Color.accentColor).font(.system(size: 9)) }
                Spacer()
                Text(item.createdAt, style: .relative).foregroundStyle(.tertiary)
                Menu {
                    Button("查看详情…", systemImage: "arrow.up.left.and.arrow.down.right") { open() }
                    Button("复制", systemImage: "doc.on.doc") { store.copy(item) }
                    Button("在 Finder 中显示", systemImage: "folder") { NSWorkspace.shared.activateFileViewerSelecting([store.url(for: item)]) }
                    Divider()
                    Button(item.isPinned ? "取消置顶" : "置顶", systemImage: "pin") { store.update(item.id) { $0.isPinned.toggle() } }
                    Button(item.isTodo ? "移出待办" : "设为待办", systemImage: "checkmark.circle") { store.update(item.id) { $0.isTodo.toggle(); $0.isDone = false } }
                    Menu("分类") {
                        Button("未分类") { store.update(item.id) { $0.category = nil } }
                        ForEach(store.manifest.categories, id: \.self) { name in
                            Button(name) { store.update(item.id) { $0.category = name } }
                        }
                    }
                    Divider()
                    Button(item.isTrashed ? "恢复收藏" : "移到回收站", systemImage: item.isTrashed ? "arrow.uturn.backward" : "trash") {
                        store.update(item.id) { $0.isTrashed.toggle() }
                    }
                } label: { Image(systemName: "ellipsis").frame(width: 16) }
                    .menuStyle(.borderlessButton).fixedSize().help("整理收藏")
            }.font(.system(size: 10))

            VStack(alignment: .leading, spacing: 9) {
                    if item.kind == .image {
                        if let image = NSImage(contentsOf: store.url(for: item)) {
                            Image(nsImage: image).resizable().scaledToFit().frame(maxWidth: .infinity, maxHeight: 175)
                                .clipShape(RoundedRectangle(cornerRadius: 7))
                        } else { Label("图片文件暂不可用", systemImage: "photo.badge.exclamationmark").foregroundStyle(.secondary) }
                    }
                    HStack(alignment: .top, spacing: 9) {
                        if item.isTodo && !item.isTrashed {
                            Button {
                                store.update(item.id) { $0.isDone.toggle() }
                            } label: {
                                Image(systemName: item.isDone ? "checkmark.circle.fill" : "circle")
                                    .foregroundStyle(item.isDone ? Color.accentColor : .secondary)
                                    .font(.system(size: 16))
                            }.buttonStyle(.plain).help(item.isDone ? "标为未完成" : "完成待办")
                        }
                        VStack(alignment: .leading, spacing: 6) {
                            Text(item.title).font(.system(size: 13, weight: .semibold))
                                .foregroundStyle(item.isDone ? .secondary : .primary)
                                .strikethrough(item.isDone).lineLimit(2).multilineTextAlignment(.leading)
                            if item.kind == .text {
                                Text(item.text).font(.system(size: 12)).foregroundStyle(.secondary)
                                    .lineLimit(4).multilineTextAlignment(.leading).lineSpacing(4)
                            } else if let path = item.originalPath {
                                Text(path).font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1).truncationMode(.middle)
                            }
                        }
                        Spacer(minLength: 0)
                    }
                }.contentShape(Rectangle()).onTapGesture { store.isEditing = true; open() }

            HStack(spacing: 6) {
                if let category = item.category {
                    Text(category).font(.system(size: 9, weight: .medium)).foregroundStyle(Color.accentColor)
                        .padding(.horizontal, 7).padding(.vertical, 3)
                        .background(Color.accentColor.opacity(0.08), in: Capsule())
                }
                Text(item.sourceApp ?? "手动收藏").font(.system(size: 10)).foregroundStyle(.tertiary).lineLimit(1)
                Spacer()
                if item.isTrashed {
                    Button("恢复") { store.update(item.id) { $0.isTrashed = false } }.font(.system(size: 10)).buttonStyle(.plain)
                } else {
                    Button { store.update(item.id) { $0.isPinned.toggle() } } label: {
                        Image(systemName: item.isPinned ? "pin.fill" : "pin")
                    }.foregroundStyle(item.isPinned ? Color.accentColor : .secondary).help("置顶")
                    Button { store.copy(item) } label: { Image(systemName: "doc.on.doc") }
                        .foregroundStyle(.secondary).padding(.leading, 7).help("复制内容")
                }
            }.font(.system(size: 11)).buttonStyle(.plain)
        }
        .padding(15)
        .background(.background.opacity(0.65), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).strokeBorder(.primary.opacity(0.06)))
        .disabled(store.isBusy)
        .onChange(of: store.isExpanded) { _, expanded in if !expanded { store.selectedID = nil } }
    }

    private var kindColor: Color {
        switch item.kind { case .text: .blue; case .image: .purple; case .file: .orange }
    }
}
