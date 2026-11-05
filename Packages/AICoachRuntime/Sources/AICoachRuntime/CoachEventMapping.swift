//
//  CoachEventMapping.swift
//  AICoachRuntime
//
//  Turns a raw tool call (name + loosely typed arguments) into a `CoachEvent`.
//  Separate from `CoachRuntime` and free of MLX types so the mapping is
//  unit-testable without a model.
//

import Foundation
import AICoachCore

/// Maps a model's raw tool calls to coach events.
public enum CoachEventMapping {

    /// Decodes and validates a raw tool call into a coach event.
    ///
    /// A call that fails validation becomes `.rejectedToolCall` rather than
    /// throwing: one bad call should not discard the turn's text, and the
    /// athlete is better served by "the coach garbled that" than by silence.
    /// - Parameters:
    ///   - name: The tool name the model called.
    ///   - arguments: The call's arguments, as plain Swift values.
    /// - Returns: `.action` for a valid call, `.rejectedToolCall` otherwise.
    public static func event(toolName name: String, arguments: [String: Any]) -> CoachEvent {
        do {
            return .action(try CoachToolDecoder.decode(name: name, arguments: arguments))
        } catch {
            return .rejectedToolCall(reason: error.localizedDescription)
        }
    }
}

/// Token counts and timings for one generation, as reported by the runtime.
///
/// The app ignores these; the evals print them so a prompt change that doubles
/// the prompt length (and halves the speed) is visible.
public struct GenerationStats: Equatable, Sendable, Codable {
    /// Tokens in the prepared prompt (chat template + tool schemas included).
    public var promptTokens: Int
    /// Tokens the model generated.
    public var generatedTokens: Int
    /// Seconds spent processing the prompt before the first token.
    public var promptSeconds: Double
    /// Seconds spent generating.
    public var generateSeconds: Double

    /// Creates a stats value.
    public init(promptTokens: Int, generatedTokens: Int, promptSeconds: Double, generateSeconds: Double) {
        self.promptTokens = promptTokens
        self.generatedTokens = generatedTokens
        self.promptSeconds = promptSeconds
        self.generateSeconds = generateSeconds
    }

    /// Generation speed in tokens per second, or `0` before any time elapsed.
    public var tokensPerSecond: Double {
        generateSeconds > 0 ? Double(generatedTokens) / generateSeconds : 0
    }
}
