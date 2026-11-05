// swift-tools-version: 5.9

import PackageDescription

/// The on-device model runtime behind the AI coach: model presets, Hugging
/// Face delivery, and the generate → tool-call → `CoachEvent` loop.
///
/// Shared by the iOS app and the `Evals/` CLI so both run the same code against
/// the model. `AICoachCore` stays MLX-free; everything that imports MLX lives
/// here.
let package = Package(
    name: "AICoachRuntime",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "AICoachRuntime", targets: ["AICoachRuntime"]),
    ],
    dependencies: [
        .package(path: "../AICoachCore"),
        .package(url: "https://github.com/ml-explore/mlx-swift-lm", from: "3.32.3"),
        .package(url: "https://github.com/huggingface/swift-transformers", from: "1.3.5"),
    ],
    targets: [
        .target(
            name: "AICoachRuntime",
            dependencies: [
                .product(name: "AICoachCore", package: "AICoachCore"),
                .product(name: "MLXLLM", package: "mlx-swift-lm"),
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
                .product(name: "Hub", package: "swift-transformers"),
                .product(name: "Tokenizers", package: "swift-transformers"),
            ]
        ),
        .testTarget(
            name: "AICoachRuntimeTests",
            dependencies: [
                "AICoachRuntime",
                .product(name: "MLXLMCommon", package: "mlx-swift-lm"),
            ]
        ),
    ]
)
