// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "RootOut",
    platforms: [.macOS(.v15)],
    targets: [
        .target(name: "RootOutCore"),
        .executableTarget(name: "RootOut", dependencies: ["RootOutCore"]),
        .testTarget(name: "RootOutCoreTests", dependencies: ["RootOutCore"]),
    ]
)
