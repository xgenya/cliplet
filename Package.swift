// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "Cliplet",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "Cliplet", targets: ["Cliplet"])
    ],
    targets: [
        .executableTarget(
            name: "Cliplet",
            path: "Sources/Cliplet",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .testTarget(
            name: "ClipletTests",
            dependencies: ["Cliplet"],
            path: "Tests/ClipletTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-strict-concurrency=complete"])]
        ),
    ]
)
