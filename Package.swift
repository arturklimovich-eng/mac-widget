// swift-tools-version:6.0
import PackageDescription

let package = Package(
    name: "NotchClaude",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(name: "NotchClaude", path: "Sources/NotchClaude")
    ]
)
