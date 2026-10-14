//
//  GenerationConfig.swift
//  AICoachCore
//
//  Single source of truth for LLM generation parameters. Both the iOS app
//  and the eval CLI read from these values to ensure consistent behavior.
//

import Foundation

/// Configuration for LLM text generation. The `production` preset is the
/// canonical configuration used by the live app.
///
/// Parameters are tuned for Gemma 3 4B QAT 4-bit:
///
/// - `temperature` — controls randomness. Lower values produce more focused,
///   deterministic output.
/// - `topP` — nucleus sampling. Only tokens whose cumulative probability
///   mass is within this threshold are considered.
/// - `repetitionPenalty` — penalises tokens that have already appeared in
///   the recent context window. Values > 1.0 discourage repetition.
/// - `repetitionContextSize` — how many recent tokens the penalty looks
///   back across.
/// - `maxTokens` — hard cap on generated tokens per response.
public struct GenerationConfig: Codable, Sendable {
    public var maxTokens: Int
    public var temperature: Float
    public var topP: Float
    public var repetitionPenalty: Float
    public var repetitionContextSize: Int

    public init(
        maxTokens: Int = 400,
        temperature: Float = 0.4,
        topP: Float = 0.9,
        repetitionPenalty: Float = 1.2,
        repetitionContextSize: Int = 200
    ) {
        self.maxTokens = maxTokens
        self.temperature = temperature
        self.topP = topP
        self.repetitionPenalty = repetitionPenalty
        self.repetitionContextSize = repetitionContextSize
    }

    /// The app's current production configuration.
    public static let production = GenerationConfig()

    /// Conversational preset used by the chat coach.
    ///
    /// Roomier and warmer than `production`, which is tuned for a terse one-shot
    /// bullet list: a conversation needs headroom for a reply plus a tool call,
    /// and reads as stilted at 0.4. `repetitionPenalty` stays at 1.2 — the
    /// degenerate looping this model falls into is real and not worth
    /// rediscovering.
    public static let chat = GenerationConfig(
        maxTokens: 512,
        temperature: 0.6,
        topP: 0.95
    )

    /// Experimental: lower repetition penalty — less needed with proper
    /// chat template formatting.
    public static let lowerRepPenalty = GenerationConfig(
        repetitionPenalty: 1.2
    )

    /// Experimental: tighter constraints for more conservative output.
    public static let conservative = GenerationConfig(
        maxTokens: 300,
        temperature: 0.3,
        topP: 0.85
    )
}
