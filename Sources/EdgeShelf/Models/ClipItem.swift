import Foundation

enum ClipKind: String, Codable, CaseIterable, Sendable {
    case text, image, file
    var title: String { switch self { case .text: "文本"; case .image: "图片"; case .file: "文件" } }
    var symbol: String { switch self { case .text: "text.alignleft"; case .image: "photo"; case .file: "doc" } }
}

struct ClipItem: Identifiable, Codable, Sendable {
    var id: UUID
    var kind: ClipKind
    var title: String
    var createdAt: Date
    var modifiedAt: Date
    var relativePath: String
    var sourceApp: String?
    var originalPath: String?
    var category: String?
    var isPinned = false
    var isTodo = false
    var isDone = false
    var isTrashed = false
    var text: String = ""

    enum CodingKeys: String, CodingKey {
        case id, kind, title, createdAt, modifiedAt, relativePath, sourceApp, originalPath
        case category, isPinned, isTodo, isDone, isTrashed
    }
}

struct LibraryManifest: Codable, Sendable {
    var version = 1
    var categories: [String] = ["工作", "生活", "灵感"]
    var items: [ClipItem] = []
}

enum CapturePayload: Sendable {
    case text(String), image(Data), files([URL])
}

enum ShelfFilter: String, CaseIterable, Identifiable {
    case all, pinned, todo, trash
    var id: Self { self }
    var title: String { switch self { case .all: "全部"; case .pinned: "置顶"; case .todo: "待办"; case .trash: "回收站" } }
    var symbol: String { switch self { case .all: "tray.full"; case .pinned: "pin"; case .todo: "checkmark.circle"; case .trash: "trash" } }
}
