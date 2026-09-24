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
            dependencies: ["ClipletKit"],
            path: "Sources/Cliplet"
        ),
        .target(
            name: "ClipletKit",
            path: "Sources/ClipletKit",
            resources: [.process("Resources")]
        ),
        .testTarget(
            name: "ClipletTests",
            dependencies: ["ClipletKit"],
            path: "Tests/ClipletTests",
            resources: [.copy("Fixtures")]
        ),
    ]
)
