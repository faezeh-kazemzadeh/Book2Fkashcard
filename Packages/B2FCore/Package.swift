// swift-tools-version:5.9
import PackageDescription

/// B2FCore holds every piece of Book2Flashcards logic that does not depend on UIKit,
/// Vision, StoreKit or SwiftData. It builds on iOS, macOS and Linux so that the
/// algorithms (FSRS, SM-2, Anki packaging, quality filtering, lesson detection, AI
/// prompting) can be unit-tested quickly on any CI runner.
let package = Package(
    name: "B2FCore",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "B2FCore", targets: ["B2FCore"])
    ],
    targets: [
        .systemLibrary(
            name: "CSQLite",
            path: "Sources/CSQLite",
            pkgConfig: "sqlite3",
            providers: [.apt(["libsqlite3-dev"])]
        ),
        .target(
            name: "B2FCore",
            dependencies: [
                .target(name: "CSQLite", condition: .when(platforms: [.linux]))
            ],
            linkerSettings: [.linkedLibrary("sqlite3")]
        ),
        .testTarget(
            name: "B2FCoreTests",
            dependencies: ["B2FCore"]
        )
    ]
)
