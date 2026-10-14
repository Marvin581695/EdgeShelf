import SwiftUI

enum DockEdge: String, CaseIterable { case left, right
    var title: String { self == .left ? "左侧" : "右侧" }
}
enum RevealMode: String, CaseIterable { case autoHide, edgeToggle
    var title: String { self == .autoHide ? "离开后自动收起" : "再次触边收起" }
}
enum PanelAnimation: String, CaseIterable { case slide, fade, none
    var title: String { switch self { case .slide: "滑入"; case .fade: "淡入"; case .none: "无动画" } }
}

@MainActor
final class Preferences: ObservableObject {
    private let defaults: UserDefaults
    @Published var edge: DockEdge { didSet { save() } }
    @Published var width: Double { didSet { save() } }
    @Published var heightRatio: Double { didSet { save() } }
    @Published var revealDelay: Double { didSet { save() } }
    @Published var hideDelay: Double { didSet { save() } }
    @Published var cornerExclusion: Double { didSet { save() } }
    @Published var hoverEnabled: Bool { didSet { save() } }
    @Published var revealMode: RevealMode { didSet { save() } }
    @Published var animation: PanelAnimation { didSet { save() } }
    @Published var screenID: String { didSet { save() } }
    @Published var copyCount: Int { didSet { save() } }
    @Published var copyInterval: Double { didSet { save() } }
    @Published var captureEnabled: Bool { didSet { save() } }
    @Published var revealAfterCapture: Bool { didSet { save() } }
    @Published var soundEnabled: Bool { didSet { save() } }
    @Published var appearance: String { didSet { save() } }
    @Published var libraryPath: String { didSet { save() } }

    init(defaults: UserDefaults = .standard) {
        self.defaults = defaults
        defaults.register(defaults: ["width": 420.0, "heightRatio": 0.94, "revealDelay": 0.25,
            "hideDelay": 0.65, "cornerExclusion": 32.0, "hoverEnabled": true,
            "copyCount": 2, "copyInterval": 0.65, "captureEnabled": true,
            "revealAfterCapture": false, "soundEnabled": true])
        edge = DockEdge(rawValue: defaults.string(forKey: "edge") ?? "") ?? .right
        width = min(640, max(360, defaults.double(forKey: "width")))
        heightRatio = min(1, max(0.5, defaults.double(forKey: "heightRatio")))
        revealDelay = defaults.double(forKey: "revealDelay")
        hideDelay = defaults.double(forKey: "hideDelay")
        cornerExclusion = defaults.double(forKey: "cornerExclusion")
        hoverEnabled = defaults.bool(forKey: "hoverEnabled")
        revealMode = RevealMode(rawValue: defaults.string(forKey: "revealMode") ?? "") ?? .autoHide
        animation = PanelAnimation(rawValue: defaults.string(forKey: "animation") ?? "") ?? .slide
        screenID = defaults.string(forKey: "screenID") ?? "auto"
        copyCount = min(5, max(2, defaults.integer(forKey: "copyCount")))
        copyInterval = defaults.double(forKey: "copyInterval")
        captureEnabled = defaults.bool(forKey: "captureEnabled")
        revealAfterCapture = defaults.bool(forKey: "revealAfterCapture")
        soundEnabled = defaults.bool(forKey: "soundEnabled")
        appearance = defaults.string(forKey: "appearance") ?? "system"
        libraryPath = defaults.string(forKey: "libraryPath") ?? ""
    }

    var libraryURL: URL {
        if !libraryPath.isEmpty { return URL(fileURLWithPath: libraryPath, isDirectory: true) }
        return FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("EdgeShelf", isDirectory: true)
    }

    private func save() {
        let values: [String: Any] = ["edge": edge.rawValue, "width": width, "heightRatio": heightRatio,
            "revealDelay": revealDelay, "hideDelay": hideDelay, "cornerExclusion": cornerExclusion,
            "hoverEnabled": hoverEnabled, "revealMode": revealMode.rawValue, "animation": animation.rawValue,
            "screenID": screenID, "copyCount": copyCount, "copyInterval": copyInterval,
            "captureEnabled": captureEnabled, "revealAfterCapture": revealAfterCapture,
            "soundEnabled": soundEnabled, "appearance": appearance, "libraryPath": libraryPath]
        values.forEach { defaults.set($0.value, forKey: $0.key) }
    }
}
