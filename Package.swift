// swift-tools-version: 6.0
import PackageDescription

let package = Package(
    name: "MacB",
    platforms: [.macOS(.v14)],
    products: [.executable(name: "MacB", targets: ["MacB"])],
    targets: [
        .target(name: "MacBCore"),
        .executableTarget(name: "MacB", dependencies: ["MacBCore"]),
        .testTarget(name: "MacBCoreTests", dependencies: ["MacBCore"])
    ],
    swiftLanguageModes: [.v5]
)
