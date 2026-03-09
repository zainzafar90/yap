// swift-tools-version: 6.0
// This Package.swift exists solely for SourceKit-LSP indexing in VS Code.
// The real build system is project.yml → XcodeGen → Yap.xcodeproj.

import PackageDescription

let package = Package(
    name: "Yap",
    platforms: [.macOS(.v15)],
    products: [
        .library(name: "Yap", targets: ["Yap"]),
    ],
    dependencies: [
        .package(url: "https://github.com/argmaxinc/WhisperKit.git", from: "0.15.0"),
        .package(url: "https://github.com/FluidInference/FluidAudio.git", branch: "main"),
        .package(url: "https://github.com/sparkle-project/Sparkle", from: "2.0.0"),
    ],
    targets: [
        .target(
            name: "Yap",
            dependencies: [
                .product(name: "WhisperKit", package: "WhisperKit"),
                .product(name: "FluidAudio", package: "FluidAudio"),
                .product(name: "Sparkle", package: "Sparkle"),
            ],
            path: "Yap"
        ),
        .testTarget(
            name: "YapTests",
            dependencies: ["Yap"],
            path: "YapTests"
        ),
    ]
)
