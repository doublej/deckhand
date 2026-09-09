// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "DeckhandKit",
    platforms: [
        .iOS(.v18),
        .macOS(.v15)
    ],
    products: [
        .library(name: "DeckhandKit", targets: ["DeckhandKit"])
    ],
    targets: [
        .target(name: "DeckhandKit"),
        .testTarget(
            name: "DeckhandKitTests",
            dependencies: ["DeckhandKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
