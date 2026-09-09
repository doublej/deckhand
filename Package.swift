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
        // Draws the app icon from DotMatrix's own geometry, so the home screen and the rail
        // cannot drift apart. macOS only, and only ever run by `just icon`.
        .executableTarget(name: "IconMaker", dependencies: ["DeckhandKit"]),
        .testTarget(
            name: "DeckhandKitTests",
            dependencies: ["DeckhandKit"],
            resources: [.copy("Fixtures")]
        )
    ]
)
