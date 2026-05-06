// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "MatchEngine",
    platforms: [
        .iOS(.v17),
        .macOS(.v13)
    ],
    products: [
        .library(name: "MatchEngine", targets: ["MatchEngine"])
    ],
    targets: [
        .target(name: "MatchEngine", path: "Sources/MatchEngine"),
        .testTarget(name: "MatchEngineTests", dependencies: ["MatchEngine"], path: "Tests/MatchEngineTests")
    ]
)
