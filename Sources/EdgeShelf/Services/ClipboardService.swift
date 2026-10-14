import AppKit

@MainActor
enum ClipboardService {
    static func snapshot() throws -> CapturePayload {
        let board = NSPasteboard.general
        if let files = board.readObjects(forClasses: [NSURL.self], options: [.urlReadingFileURLsOnly: true]) as? [URL], !files.isEmpty {
            return .files(files)
        }
        if let png = board.data(forType: .png) { return .image(png) }
        if let tiff = board.data(forType: .tiff),
           let bitmap = NSBitmapImageRep(data: tiff), let png = bitmap.representation(using: .png, properties: [:]) {
            return .image(png)
        }
        if let text = board.string(forType: .string), !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            return .text(text)
        }
        throw LibraryError.emptyContent
    }
}
