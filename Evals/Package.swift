// swift-tools-version: 5.9

import PackageDescription

/// The AI coach eval suite.
///
/// - `CoachEvalKit`: scenarios, expectations, the runner, and reports. Depends
///   only on AICoachCore, so it is unit-testable with `swift test` and never
///   needs a model.
/// - `CoachEval`: the `coach-eval` command-line tool. Adds AICoachRuntime —
///   the same package the iOS app generates through — to run scenarios
///   against the real model on the Mac's GPU.
let package = Package(
    name: "CoachEval",
    platforms: [.macOS(.v14)],
    dependencies: [
        .package(path: "../Packages/AICoachCore"),
        .package(path: "../Packages/AICoachRuntime"),
        .package(
            url: "https://github.com/apple/swift-argument-parser",
            from: "1.3.0"
        ),
    ],
    targets: [
        .target(
            name: "CoachEvalKit",
            dependencies: [
                .product(name: "AICoachCore", package: "AICoachCore"),
            ]
        ),
        .executableTarget(
            name: "CoachEval",
            dependencies: [
                "CoachEvalKit",
                .product(name: "AICoachCore", package: "AICoachCore"),
                .product(name: "AICoachRuntime", package: "AICoachRuntime"),
                .product(name: "ArgumentParser", package: "swift-argument-parser"),
            ],
            path: "Sources/CoachEval"
        ),
        .testTarget(
            name: "CoachEvalKitTests",
            dependencies: ["CoachEvalKit"]
        ),
    ]
)
