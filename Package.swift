// swift-tools-version:5.9
import PackageDescription

let package = Package(
    name: "MyBrowser",
    platforms: [.macOS(.v13)],
    targets: [
        .executableTarget(name: "MyBrowser", path: "Sources/MyBrowser")
    ]
)
