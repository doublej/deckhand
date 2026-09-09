// swift-tools-version: 6.2
import PackageDescription

let package = Package(
    name: "Deckhand",
    platforms: [
        .iOS(.v26)
    ],
    targets: [
        .executableTarget(
            name: "Deckhand",
            path: "deckhand"
        )
    ]
)
