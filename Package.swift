// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Screenz",
    platforms: [.macOS(.v13)],
    products: [.executable(name: "Screenz", targets: ["Screenz"])],
    targets: [
        .target(name: "ScreenzCore"),
        .executableTarget(name: "Screenz", dependencies: ["ScreenzCore"], resources: [.copy("Resources/phone.html")]),
        .testTarget(name: "ScreenzCoreTests", dependencies: ["ScreenzCore"]),
        .testTarget(name: "ScreenzTests", dependencies: ["Screenz", "ScreenzCore"])
    ]
)
