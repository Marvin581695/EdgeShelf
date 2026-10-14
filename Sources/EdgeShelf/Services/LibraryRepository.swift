import Foundation

enum LibraryError: LocalizedError {
    case invalidPath, unsupportedVersion, emptyContent, missingContent(String), duplicateCategory
    var errorDescription: String? {
        switch self {
        case .invalidPath: "资料路径无效，已停止操作以保护数据。"
        case .unsupportedVersion: "资料库版本较新，请使用更新版本打开。"
        case .emptyContent: "剪贴板里没有可以收藏的文本、图片或文件。"
        case .missingContent(let name): "找不到「\(name)」的内容文件，请检查资料库。"
        case .duplicateCategory: "分类名称为空或已存在。"
        }
    }
}

/// Owns all disk operations, including copying large attachments, off the main thread.
actor LibraryRepository {
    let root: URL
    private let fm = FileManager.default
    private var manifest = LibraryManifest()
    private var loaded = false

    init(root: URL) { self.root = root.standardizedFileURL }

    func load() throws -> LibraryManifest {
        loaded = false
        try fm.createDirectory(at: root, withIntermediateDirectories: true)
        let index = root.appendingPathComponent("index.json")
        var next: LibraryManifest
        if fm.fileExists(atPath: index.path) {
            next = try JSONDecoder.shelf.decode(LibraryManifest.self, from: Data(contentsOf: index))
            guard next.version == 1 else { throw LibraryError.unsupportedVersion }
        } else {
            // An existing data directory without its index must never be silently overwritten.
            let items = root.appendingPathComponent("items")
            if fm.fileExists(atPath: items.path), !(try fm.contentsOfDirectory(atPath: items.path)).isEmpty {
                throw LibraryError.missingContent("index.json")
            }
            next = LibraryManifest()
            try persist(next)
        }
        for i in next.items.indices {
            let url = try contentURL(next.items[i].relativePath)
            if next.items[i].kind == .text {
                guard fm.fileExists(atPath: url.path) else { throw LibraryError.missingContent(next.items[i].title) }
                next.items[i].text = try String(contentsOf: url, encoding: .utf8)
            }
        }
        manifest = next
        loaded = true
        return next
    }

    func capture(_ payload: CapturePayload, source: String?, category: String?) throws -> LibraryManifest {
        guard loaded else { throw LibraryError.missingContent("index.json") }
        var next = manifest
        var createdDirectories: [URL] = []
        func makeItem(kind: ClipKind, title: String, filename: String, original: String? = nil) throws -> (ClipItem, URL) {
            let id = UUID()
            let directory = root.appendingPathComponent("items/\(id.uuidString)", isDirectory: true)
            try fm.createDirectory(at: directory, withIntermediateDirectories: true)
            createdDirectories.append(directory)
            let relative = "items/\(id.uuidString)/\(filename)"
            let item = ClipItem(id: id, kind: kind, title: title, createdAt: Date(), modifiedAt: Date(),
                                relativePath: relative, sourceApp: source, originalPath: original, category: category)
            return (item, directory.appendingPathComponent(filename))
        }
        do {
            switch payload {
            case .text(let text):
                guard !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { throw LibraryError.emptyContent }
                let title = String(text.split(whereSeparator: \.isNewline).first.map(String.init)?.prefix(72) ?? "文本")
                var (item, url) = try makeItem(kind: .text, title: title, filename: "content.md")
                try Data(text.utf8).write(to: url, options: .atomic)
                item.text = text
                next.items.insert(item, at: 0)
            case .image(let data):
                guard !data.isEmpty else { throw LibraryError.emptyContent }
                let (item, url) = try makeItem(kind: .image, title: "图片 · \(Date().formatted(date: .abbreviated, time: .shortened))", filename: "image.png")
                try data.write(to: url, options: .atomic)
                next.items.insert(item, at: 0)
            case .files(let urls):
                guard !urls.isEmpty else { throw LibraryError.emptyContent }
                for sourceURL in urls {
                    guard sourceURL.isFileURL else { throw LibraryError.invalidPath }
                    let scoped = sourceURL.startAccessingSecurityScopedResource()
                    defer { if scoped { sourceURL.stopAccessingSecurityScopedResource() } }
                    // Prevent recursively copying the library into itself.
                    let realSource = sourceURL.resolvingSymlinksInPath().standardizedFileURL.path
                    let realRoot = root.resolvingSymlinksInPath().path
                    guard realSource != realRoot, !realRoot.hasPrefix(realSource + "/"),
                          !realSource.hasPrefix(realRoot + "/") else { throw LibraryError.invalidPath }
                    let (item, url) = try makeItem(kind: .file, title: sourceURL.lastPathComponent,
                                                  filename: sourceURL.lastPathComponent, original: sourceURL.path)
                    try fm.copyItem(at: sourceURL, to: url)
                    next.items.insert(item, at: 0)
                }
            }
            try persist(next)
            manifest = next
            return next
        } catch {
            createdDirectories.forEach { try? fm.removeItem(at: $0) }
            throw error
        }
    }

    func update(_ item: ClipItem) throws -> LibraryManifest {
        guard loaded, let index = manifest.items.firstIndex(where: { $0.id == item.id }) else { throw LibraryError.invalidPath }
        var next = manifest
        var updated = item
        updated.modifiedAt = Date()
        let old = manifest.items[index]
        guard updated.relativePath == old.relativePath, updated.kind == old.kind else { throw LibraryError.invalidPath }
        let url = try contentURL(item.relativePath)
        let changedText = item.kind == .text && item.text != old.text
        if changedText { try Data(item.text.utf8).write(to: url, options: .atomic) }
        next.items[index] = updated
        do { try persist(next) } catch {
            if changedText { try? Data(old.text.utf8).write(to: url, options: .atomic) }
            throw error
        }
        manifest = next
        return next
    }

    func addCategory(_ raw: String) throws -> LibraryManifest {
        guard loaded else { throw LibraryError.invalidPath }
        let name = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, !manifest.categories.contains(name) else { throw LibraryError.duplicateCategory }
        var next = manifest
        next.categories.append(name)
        try persist(next)
        manifest = next
        return next
    }

    func contentURL(_ relativePath: String) throws -> URL {
        let parts = relativePath.split(separator: "/").map(String.init)
        guard !relativePath.hasPrefix("/"), parts.first == "items", parts.count >= 3,
              !parts.contains(".."), !parts.contains(".") else { throw LibraryError.invalidPath }
        // resolvingSymlinksInPath alone can leave a path unresolved if the final file is missing.
        // Reject symlinks component by component, including dangling links.
        var componentURL = root
        for part in parts {
            componentURL.appendPathComponent(part)
            if (try? fm.destinationOfSymbolicLink(atPath: componentURL.path)) != nil { throw LibraryError.invalidPath }
        }
        let url = root.appendingPathComponent(relativePath).standardizedFileURL
        let resolved = url.resolvingSymlinksInPath().path
        guard resolved.hasPrefix(root.resolvingSymlinksInPath().path + "/items/") else { throw LibraryError.invalidPath }
        return url
    }

    private func persist(_ value: LibraryManifest) throws {
        try JSONEncoder.shelf.encode(value).write(to: root.appendingPathComponent("index.json"), options: .atomic)
    }
}

extension JSONEncoder {
    static var shelf: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return encoder
    }
}
extension JSONDecoder {
    static var shelf: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}
