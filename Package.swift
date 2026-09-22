// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ClipboardNative",
    defaultLocalization: "en",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "ClipboardNative", targets: ["ClipboardNative"])
    ],
    targets: [
        .executableTarget(
            name: "ClipboardNative",
            path: "Sources/ClipboardNative",
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-strict-concurrency=complete"])]
        ),
        .testTarget(
            name: "ClipboardNativeTests",
            dependencies: ["ClipboardNative"],
            path: "Tests/ClipboardNativeTests",
            resources: [.copy("Fixtures")],
            swiftSettings: [.swiftLanguageMode(.v5), .unsafeFlags(["-strict-concurrency=complete"])]
        ),
    ]
)
