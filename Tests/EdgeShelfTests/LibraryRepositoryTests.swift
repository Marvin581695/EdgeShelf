import XCTest
@testable import EdgeShelf

final class LibraryRepositoryTests: XCTestCase {
    private func temporaryRoot() throws -> URL {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("EdgeShelfTests-\(UUID())")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        addTeardownBlock { try? FileManager.default.removeItem(at: root) }
        return root
    }

    func testMarkdownAndMetadataRoundTripWithExternalEdit() async throws {
        let root = try temporaryRoot()
        let repository = LibraryRepository(root: root)
        _ = try await repository.load()
        let text = "# 灵感\n\n- [ ] 记得完成\n`hello` 🧩"
        let captured = try await repository.capture(.text(text), source: "Safari", category: "工作")
        var item = try XCTUnwrap(captured.items.first)
        let url = root.appendingPathComponent(item.relativePath)
        XCTAssertEqual(try String(contentsOf: url, encoding: .utf8), text)
        item.isPinned = true; item.isTodo = true; item.isDone = true
        _ = try await repository.update(item)
        let reopened = LibraryRepository(root: root)
        let loaded = try await reopened.load()
        XCTAssertTrue(loaded.items[0].isPinned)
        XCTAssertTrue(loaded.items[0].isDone)
        XCTAssertEqual(loaded.items[0].category, "工作")
        XCTAssertEqual(loaded.items[0].sourceApp, "Safari")
        XCTAssertEqual(loaded.items[0].text, text)
        try Data("外部编辑".utf8).write(to: url, options: .atomic)
        let refreshed = try await reopened.load()
        XCTAssertEqual(refreshed.items[0].text, "外部编辑")
        let index = try String(contentsOf: root.appendingPathComponent("index.json"), encoding: .utf8)
        XCTAssertFalse(index.contains("记得完成"), "The index stores metadata, not a duplicate text body")
    }

    func testFileSnapshotSurvivesSourceDeletionAndTrashRestore() async throws {
        let parent = try temporaryRoot()
        let root = parent.appendingPathComponent("Library")
        let source = parent.appendingPathComponent("资料.txt")
        try Data("original".utf8).write(to: source)
        let repository = LibraryRepository(root: root)
        _ = try await repository.load()
        let result = try await repository.capture(.files([source]), source: "Finder", category: nil)
        var item = try XCTUnwrap(result.items.first)
        try FileManager.default.removeItem(at: source)
        let saved = root.appendingPathComponent(item.relativePath)
        XCTAssertEqual(try String(contentsOf: saved, encoding: .utf8), "original")
        item.isTrashed = true
        _ = try await repository.update(item)
        let trash = try await repository.load()
        XCTAssertTrue(trash.items[0].isTrashed)
        XCTAssertTrue(FileManager.default.fileExists(atPath: saved.path))
        item.isTrashed = false
        _ = try await repository.update(item)
        let restored = try await repository.load()
        XCTAssertFalse(restored.items[0].isTrashed)
    }

    func testBatchFailureRollsBackCopiedAttachmentsAndIndex() async throws {
        let parent = try temporaryRoot()
        let root = parent.appendingPathComponent("Library")
        let source = parent.appendingPathComponent("exists.txt")
        try Data("hello".utf8).write(to: source)
        let repository = LibraryRepository(root: root)
        _ = try await repository.load()
        do {
            _ = try await repository.capture(.files([source, parent.appendingPathComponent("missing")]), source: nil, category: nil)
            XCTFail("Missing second file should fail the batch")
        } catch { }
        let result = try await repository.load()
        XCTAssertTrue(result.items.isEmpty)
        XCTAssertEqual(try FileManager.default.contentsOfDirectory(atPath: root.appendingPathComponent("items").path).count, 0)
    }

    func testRejectsLibraryRecursionAndPathTraversal() async throws {
        let root = try temporaryRoot()
        let repository = LibraryRepository(root: root)
        _ = try await repository.load()
        for path in ["../secret", "/tmp/secret", "items/../../secret"] {
            do { _ = try await repository.contentURL(path); XCTFail("Should reject \(path)") } catch { }
        }
        do { _ = try await repository.capture(.files([root]), source: nil, category: nil); XCTFail("Recursive copy") } catch { }
        let target = root.appendingPathComponent("items/link")
        try FileManager.default.createDirectory(at: root.appendingPathComponent("items"), withIntermediateDirectories: true)
        try FileManager.default.createSymbolicLink(at: target, withDestinationURL: root.deletingLastPathComponent())
        do { _ = try await repository.contentURL("items/link/secret"); XCTFail("Symlink escape") } catch { }
    }

    func testCorruptIndexIsPreservedAndCaptureBlocked() async throws {
        let root = try temporaryRoot()
        let bad = Data("{broken".utf8)
        let index = root.appendingPathComponent("index.json")
        try bad.write(to: index)
        let repository = LibraryRepository(root: root)
        do { _ = try await repository.load(); XCTFail("Must report corrupted index") } catch { }
        do { _ = try await repository.capture(.text("do not save"), source: nil, category: nil); XCTFail("Must block mutations") } catch { }
        XCTAssertEqual(try Data(contentsOf: index), bad)
    }

    func testMissingIndexDoesNotOverwriteExistingData() async throws {
        let root = try temporaryRoot()
        let directory = root.appendingPathComponent("items/old-item")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        let note = directory.appendingPathComponent("content.md")
        try Data("precious".utf8).write(to: note)
        let repository = LibraryRepository(root: root)
        do { _ = try await repository.load(); XCTFail("Missing index must be reported") } catch { }
        XCTAssertFalse(FileManager.default.fileExists(atPath: root.appendingPathComponent("index.json").path))
        XCTAssertEqual(try String(contentsOf: note, encoding: .utf8), "precious")
    }

    func testImageBytesAndCategoriesPersist() async throws {
        let root = try temporaryRoot()
        let repository = LibraryRepository(root: root)
        _ = try await repository.load()
        let added = try await repository.addCategory("  项目 A  ")
        XCTAssertTrue(added.categories.contains("项目 A"))
        do { _ = try await repository.addCategory("项目 A"); XCTFail("Duplicate category") } catch { }
        let data = Data([137, 80, 78, 71, 13, 10, 26, 10])
        let captured = try await repository.capture(.image(data), source: "Preview", category: "项目 A")
        let item = try XCTUnwrap(captured.items.first)
        XCTAssertEqual(item.kind, .image)
        XCTAssertEqual(try Data(contentsOf: root.appendingPathComponent(item.relativePath)), data)
        let loaded = try await repository.load()
        XCTAssertTrue(loaded.categories.contains("项目 A"))
    }
}
