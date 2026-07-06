// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "SwiftAIKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "SwiftAIKit",
            targets: ["SwiftAIKit"]
        ),
        .library(
            name: "SwiftAIKitUI",
            targets: ["SwiftAIKitUI"]
        ),
        .library(
            name: "SwiftAIKitImage",
            targets: ["SwiftAIKitImage"]
        ),
    ],
    targets: [
        .target(
            name: "SwiftAIKit",
            path: "Sources/SwiftAIKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .target(
            name: "SwiftAIKitUI",
            dependencies: ["SwiftAIKit"],
            path: "Sources/SwiftAIKitUI",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SwiftAIKitTests",
            dependencies: ["SwiftAIKit"],
            path: "Tests/SwiftAIKitTests"
        ),
        .testTarget(
            name: "SwiftAIKitUITests",
            dependencies: ["SwiftAIKitUI"],
            path: "Tests/SwiftAIKitUITests"
        ),
        .target(
            name: "SwiftAIKitImage",
            dependencies: ["SwiftAIKit"],
            path: "Sources/SwiftAIKitImage",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SwiftAIKitImageTests",
            dependencies: ["SwiftAIKitImage"],
            path: "Tests/SwiftAIKitImageTests"
        ),
    ]
)
