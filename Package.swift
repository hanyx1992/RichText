// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "RichText",
    platforms: [
        .macOS(.v13),
        .iOS(.v16),
    ],
    products: [
        .library(
            name: "RichText",
            targets: [
                "RichText",
            ]
        ),
    ],
    targets: [
        .target(
            name: "RichText",
            dependencies: [
                "Introspection"
            ]
        ),
        .target(
            name: "Introspection"
        ),
        .testTarget(
            name: "RichTextTests",
            dependencies: ["RichText"]
        ),
    ]
)
