// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "DeskMap",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "DeskMap", path: "Sources/DeskMap")
    ]
)
