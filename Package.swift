// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "EdgeShelf",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "EdgeShelf", targets: ["EdgeShelf"])],
    targets: [
        .executableTarget(name: "EdgeShelf"),
        .testTarget(name: "EdgeShelfTests", dependencies: ["EdgeShelf"])
    ],
    swiftLanguageModes: [.v5]
)
