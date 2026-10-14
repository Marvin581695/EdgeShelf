import AppKit
import SwiftUI

@MainActor
final class ShelfStore: ObservableObject {
    @Published private(set) var manifest = LibraryManifest()
    @Published private(set) var isBusy = false
    @Published private(set) var isReady = false
    @Published var errorMessage: String?
    @Published var notice: String?
    @Published var query = ""
    @Published var filter: ShelfFilter = .all
    @Published var category: String?
    @Published var kind: ClipKind?
    @Published var selectedID: UUID?
    @Published var keepExpanded = false
    @Published var isExpanded = false
    @Published var isEditing = false
    let preferences: Preferences
    private var repository: LibraryRepository
    var didCapture: (() -> Void)?

    init(preferences: Preferences) {
        self.preferences = preferences
        repository = LibraryRepository(root: preferences.libraryURL)
    }

    var items: [ClipItem] {
        manifest.items.filter { item in
            let matchesFilter: Bool
            switch filter {
            case .all: matchesFilter = !item.isTrashed
            case .pinned: matchesFilter = !item.isTrashed && item.isPinned
            case .todo: matchesFilter = !item.isTrashed && item.isTodo
            case .trash: matchesFilter = item.isTrashed
            }
            return matchesFilter && (category == nil || item.category == category)
                && (kind == nil || item.kind == kind)
                && (query.isEmpty || "\(item.title) \(item.text) \(item.sourceApp ?? "") \(item.originalPath ?? "")"
                    .localizedCaseInsensitiveContains(query))
        }.sorted {
            if $0.isPinned != $1.isPinned { return $0.isPinned }
            return $0.createdAt > $1.createdAt
        }
    }
    var activeCount: Int { manifest.items.filter { !$0.isTrashed }.count }
    var todoCount: Int { manifest.items.filter { !$0.isTrashed && $0.isTodo && !$0.isDone }.count }
    var selected: ClipItem? { manifest.items.first { $0.id == selectedID } }

    func load() {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do { manifest = try await repository.load(); isReady = true }
            catch { isReady = false; errorMessage = error.localizedDescription }
        }
    }

    func switchLibrary(to url: URL) {
        guard !isBusy else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do {
                let candidate = LibraryRepository(root: url)
                let next = try await candidate.load()
                repository = candidate
                manifest = next
                preferences.libraryPath = url.path
                selectedID = nil; category = nil; query = ""; isReady = true
                notice = "已打开资料库"
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func captureClipboard(source: String? = nil) {
        do { capture(try ClipboardService.snapshot(), source: source ?? NSWorkspace.shared.frontmostApplication?.localizedName) }
        catch { errorMessage = error.localizedDescription }
    }

    func capture(_ payload: CapturePayload, source: String?) {
        guard canMutate() else { return }
        isBusy = true
        let targetCategory = category
        Task {
            defer { isBusy = false }
            do {
                manifest = try await repository.capture(payload, source: source, category: targetCategory)
                selectedID = manifest.items.first?.id
                notice = "已收藏到\(targetCategory ?? "收纳箱")"
                if preferences.soundEnabled { NSSound(named: "Pop")?.play() }
                didCapture?()
            } catch { errorMessage = error.localizedDescription }
        }
    }

    func update(_ id: UUID, change: @escaping (inout ClipItem) -> Void) {
        guard canMutate(), var item = manifest.items.first(where: { $0.id == id }) else { return }
        change(&item)
        save(item)
    }

    func save(_ item: ClipItem) {
        guard canMutate() else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do { manifest = try await repository.update(item); notice = "已保存" }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func addCategory(_ name: String) {
        guard canMutate() else { return }
        isBusy = true
        Task {
            defer { isBusy = false }
            do { manifest = try await repository.addCategory(name); category = name.trimmingCharacters(in: .whitespacesAndNewlines) }
            catch { errorMessage = error.localizedDescription }
        }
    }

    func url(for item: ClipItem) -> URL {
        // All paths are validated by the repository before the manifest reaches the UI.
        preferences.libraryURL.appendingPathComponent(item.relativePath)
    }

    func copy(_ item: ClipItem) {
        do {
            let url = url(for: item)
            if item.kind != .text, !FileManager.default.fileExists(atPath: url.path) {
                throw LibraryError.missingContent(item.title)
            }
            let pasteboard = NSPasteboard.general
            pasteboard.clearContents()
            switch item.kind {
            case .text: pasteboard.setString(item.text, forType: .string)
            case .image:
                let data = try Data(contentsOf: url)
                pasteboard.setData(data, forType: .png)
            case .file: pasteboard.writeObjects([url as NSURL])
            }
            notice = "已复制，可在其他应用粘贴"
        } catch { errorMessage = error.localizedDescription }
    }

    func chooseFiles() {
        let panel = NSOpenPanel()
        panel.title = "收藏文件或文件夹"
        panel.canChooseFiles = true; panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        if panel.runModal() == .OK { capture(.files(panel.urls), source: "Finder") }
    }

    private func canMutate() -> Bool {
        guard isReady else { errorMessage = "资料库尚未就绪，请先重新加载。"; return false }
        guard !isBusy else { errorMessage = "正在保存资料，请稍后再试。"; return false }
        return true
    }
}
