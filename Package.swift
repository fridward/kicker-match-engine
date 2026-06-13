// swift-tools-version: 6.1
// Geteilte, deterministische Match-Engine — von der iOS-App (XcodeGen, nativ),
// dem Backend (Vapor) UND — seit dem Android-Solo-Port — der Android-App
// (kicker-android, transpiliert via Skip) genutzt. Gleicher Seed → gleicher
// Output auf allen Plattformen.
//
// Skip-Enabling (skip-Dependency + skipstone-Plugin + dynamic Library) ist nötig,
// damit `kicker-game-core` (das diese Engine konsumiert) nach Kotlin/Compose
// transpiliert werden kann. Reines Foundation, keine UI — daher Logik-Modul
// ohne skip-ui.
//
// ACHTUNG Backend: Das Backend pinnt match-engine bewusst auf einen Pre-Skip-
// Commit (siehe kicker-backend/Package.swift), damit das Skip-Toolchain-
// Dependency NICHT in den Linux/Docker-Build leckt.
import PackageDescription

let package = Package(
    name: "MatchEngine",
    defaultLocalization: "en",
    platforms: [
        .iOS(.v17),
        .macOS(.v14)
    ],
    products: [
        .library(name: "MatchEngine", type: .dynamic, targets: ["MatchEngine"])
    ],
    dependencies: [
        .package(url: "https://source.skip.tools/skip.git", from: "1.9.2"),
        // SkipFoundation bringt für den Android-Build die Gradle-Plugin-
        // Konvention (android-library) mit — ohne ein Skip-Produkt-Dependency
        // erzeugt skipstone ein build.gradle.kts ohne android{}/api-DSL.
        .package(url: "https://source.skip.tools/skip-foundation.git", from: "1.4.0"),
    ],
    targets: [
        .target(
            name: "MatchEngine",
            dependencies: [
                .product(name: "SkipFoundation", package: "skip-foundation"),
            ],
            path: "Sources/MatchEngine",
            plugins: [.plugin(name: "skipstone", package: "skip")]
        ),
        .testTarget(
            name: "MatchEngineTests",
            dependencies: ["MatchEngine"],
            path: "Tests/MatchEngineTests",
            plugins: [.plugin(name: "skipstone", package: "skip")]
        )
    ]
)
