// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "XWriter",
    platforms: [.macOS(.v14)],
    targets: [.executableTarget(name: "XWriter", path: "Sources/XWriter")],
    swiftLanguageModes: [.v5]
)
