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
    dependencies: [
        .package(url: "https://github.com/apple/swift-testing.git", from: "0.0.0"),
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
            dependencies: [
                "SwiftAIKit",
                .product(name: "Testing", package: "swift-testing"),
            ],
            path: "Tests/SwiftAIKitTests"
        ),
    ]
)
