import AppKit
import UniformTypeIdentifiers

@MainActor
enum DropService {
    static func receive(_ providers: [NSItemProvider], store: ShelfStore) -> Bool {
        guard !providers.isEmpty, store.isReady, !store.isBusy else { return false }
        let files = providers.filter { $0.hasItemConformingToTypeIdentifier(UTType.fileURL.identifier) }
        if !files.isEmpty {
            let group = DispatchGroup()
            var urls: [URL] = []
            var failed = false
            for provider in files {
                group.enter()
                provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { object, _ in
                    let url: URL?
                    if let value = object as? URL { url = value }
                    else if let data = object as? Data { url = URL(dataRepresentation: data, relativeTo: nil) }
                    else { url = nil }
                    DispatchQueue.main.async {
                        if let url { urls.append(url) } else { failed = true }
                        group.leave()
                    }
                }
            }
            group.notify(queue: .main) {
                if failed { store.errorMessage = "部分拖入的文件无法读取，请重试。" }
                else { store.capture(.files(urls), source: "拖放") }
            }
            return true
        }
        guard let provider = providers.first else { return false }
        for type in [UTType.png, .tiff, .utf8PlainText] where provider.hasItemConformingToTypeIdentifier(type.identifier) {
            provider.loadDataRepresentation(forTypeIdentifier: type.identifier) { data, error in
                DispatchQueue.main.async {
                    guard let data else { store.errorMessage = error?.localizedDescription ?? "无法读取拖入的内容。"; return }
                    if type == .utf8PlainText, let text = String(data: data, encoding: .utf8) {
                        store.capture(.text(text), source: "拖放")
                    } else if let bitmap = NSBitmapImageRep(data: data), let png = bitmap.representation(using: .png, properties: [:]) {
                        store.capture(.image(png), source: "拖放")
                    } else { store.errorMessage = "暂不支持此内容格式。" }
                }
            }
            return true
        }
        return false
    }
}
