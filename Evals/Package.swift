// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "CoachEval",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Packages/AICoachCore"),
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
    ],
    targets: [
        .executableTarget(
            name: "CoachEval",
            dependencies: [
                .product(name: "AICoachCore", package: "AICoachCore"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CoachEval"
        ),
    ]
)
