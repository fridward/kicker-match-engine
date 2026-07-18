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
import Foundation

// Kotlin/Skip-Paritätstests sind OPT-IN: nur mit `SKIP_PARITY=1 swift test`
// (bzw. `skip test`) trägt das Test-Target das skipstone-Plugin + SkipTest und
// fährt die XCTest-Suite zusätzlich transpiliert auf der JVM. Ohne die Variable
// (Default: CI, run-all-tests.sh, schnelle lokale Läufe) läuft NUR die Swift-
// Suite — kein Gradle/Android-Toolchain nötig, keine ~9 s Extra-Last.
let parityTests = ProcessInfo.processInfo.environment["SKIP_PARITY"] == "1"

let testDependencies: [Target.Dependency] = parityTests
    ? [
        "MatchEngine",
        .product(name: "SkipTest", package: "skip"),
        .product(name: "SkipFoundation", package: "skip-foundation"),
      ]
    : ["MatchEngine"]

let testPlugins: [Target.PluginUsage] = parityTests
    ? [.plugin(name: "skipstone", package: "skip")]
    : []

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
            dependencies: testDependencies,
            path: "Tests/MatchEngineTests",
            plugins: testPlugins
        )
    ]
)
