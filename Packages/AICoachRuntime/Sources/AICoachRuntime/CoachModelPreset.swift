//
//  CoachModelPreset.swift
//  AICoachRuntime
//
//  Everything that has to change together when the coach's model changes.
//  Kept free of MLX types so it compiles (and can be tested) without the
//  runtime, and so the app and the evals read one definition.
//

import Foundation

/// A model the coach can run, plus the runtime settings that must match it.
///
/// The fields here are coupled: a Gemma 4 repository needs the `gemma4` tool
/// dialect and the `<turn|>` end-of-turn token, and getting either wrong fails
/// silently (tool calls arrive as plain text, or generation never stops). Keep
/// them in one value so they can only be swapped as a set.
public struct CoachModelPreset: Equatable, Sendable {

    /// Hugging Face repository identifier.
    public let id: String

    /// Extra end-of-generation tokens beyond the tokenizer's own `eos_token`.
    public let extraEOSTokens: Set<String>

    /// Raw value of the runtime's `ToolCallFormat` for this model family
    /// (e.g. `"gemma4"`). Stored as a string so this type needs no MLX import.
    public let toolCallFormat: String

    /// Approximate download size, for UI shown before any network use. The
    /// downloader reports exact bytes once it starts.
    public let approximateDownloadBytes: Int64

    /// Creates a preset.
    public init(
        id: String,
        extraEOSTokens: Set<String>,
        toolCallFormat: String,
        approximateDownloadBytes: Int64
    ) {
        self.id = id
        self.extraEOSTokens = extraEOSTokens
        self.toolCallFormat = toolCallFormat
        self.approximateDownloadBytes = approximateDownloadBytes
    }
}

extension CoachModelPreset {

    /// The model the app ships: Gemma 4 E2B, 4-bit.
    ///
    /// The `gemma4` model type is multimodal; MLXLLM's `Gemma4Model` reads the
    /// nested `text_config` and drops the `vision_tower` /
    /// `multi_modal_projector` weights, so it loads text-only.
    ///
    /// Why this repo and not `mlx-community/gemma-4-E2B-it-qat-mobile`, which is
    /// smaller (2.40 GB): that one is Google QAT (`quant_method: "gemma"`), not
    /// an MLX conversion. It has no `.scales`/`.biases` tensors, its
    /// `quantization_config` is regex-keyed with `num_bits` of 2/4/8, and it
    /// declares no `group_size` at all — so mlx-swift-lm cannot load it, and the
    /// missing group size is not recoverable. Every other published Gemma 4 MLX
    /// build is 5.4 GB or larger.
    ///
    /// At 4.34 GB this is appreciably heavier than the Gemma 3 4B QAT build it
    /// replaced (3.00 GB); watch for jetsam on non-Pro devices. The repo does
    /// ship `tokenizer_config.json` (with an inline chat template and
    /// `eot_token` of `<turn|>`), so tokenizer metadata needs no fallback.
    ///
    /// Gemma 4 calls tools as `<|tool_call>` / `<tool_call|>` with a `<|"|>`
    /// escape marker (Gemma 3 used `<start_function_call>`), and ends a turn
    /// with `<turn|>` (Gemma 3: `<end_of_turn>`).
    public static let production = CoachModelPreset(
        id: "lmstudio-community/gemma-4-E2B-it-MLX-4bit",
        extraEOSTokens: ["<turn|>"],
        toolCallFormat: "gemma4",
        approximateDownloadBytes: 4_372_000_000
    )
}
