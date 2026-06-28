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
    ],
    targets: [
        .target(
            name: "SwiftAIKit",
            path: "Sources/SwiftAIKit",
            swiftSettings: [
                .swiftLanguageMode(.v6),
            ]
        ),
        .testTarget(
            name: "SwiftAIKitTests",
            dependencies: ["SwiftAIKit"],
            path: "Tests/SwiftAIKitTests"
        ),
    ]
)
