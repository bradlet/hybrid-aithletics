//
//  TurnTranscript.swift
//  CoachEvalKit
//
//  What the coach produced for one turn, folded from its event stream exactly
//  the way the app's CoachChatStore folds it.
//

import Foundation
import AICoachCore

/// Token counts and timings for one generated turn.
///
/// Mirrors AICoachRuntime's `GenerationStats` without depending on it, so this
/// library stays MLX-free and testable without a model.
public struct TurnStats: Codable, Equatable, Sendable {
    /// Tokens in the prepared prompt (chat template + tool schemas included).
    public var promptTokens: Int
    /// Tokens the model generated.
    public var generatedTokens: Int
    /// Seconds spent processing the prompt.
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

    /// Generation speed, or `0` before any time elapsed.
    public var tokensPerSecond: Double {
        generateSeconds > 0 ? Double(generatedTokens) / generateSeconds : 0
    }
}

/// One coach turn as the athlete would experience it.
///
/// `fold(_:)` applies the same rules as `CoachChatStore.stream`:
/// - text chunks and `chat` tool replies both become visible reply text;
/// - the **first** proposal of the turn wins and later ones are ignored (a
///   small model often emits the same call two or three times, each slightly
///   different);
/// - rejected tool calls are kept, because in the app they show up as an
///   apology in the chat.
public struct TurnTranscript: Equatable, Sendable {
    /// Everything the athlete would read, in order.
    public var reply: String = ""
    /// The proposal card the athlete would see, if any.
    public var proposal: CoachAction?
    /// How many further proposals arrived after the first and were ignored.
    public var ignoredProposals: Int = 0
    /// Reasons for tool calls the decoder (or the runtime's parser) refused.
    public var rejections: [String] = []
    /// Token counts and timings, when the generator reports them.
    public var stats: TurnStats?
    /// Every event, unfolded, for debugging.
    public var events: [CoachEvent] = []

    /// Creates an empty transcript.
    public init() {}

    /// Folds one event into the transcript.
    public mutating func fold(_ event: CoachEvent) {
        events.append(event)
        switch event {
        case .textChunk(let text):
            reply += text
        case .action(.reply(let text)):
            reply += text
        case .action(let action):
            if proposal == nil {
                proposal = action
            } else {
                ignoredProposals += 1
            }
        case .rejectedToolCall(let reason):
            rejections.append(reason)
        }
    }

    /// Builds a transcript from a list of events.
    public static func folding(_ events: [CoachEvent]) -> TurnTranscript {
        var transcript = TurnTranscript()
        events.forEach { transcript.fold($0) }
        return transcript
    }

    /// Drains an event stream into a transcript.
    /// - Parameter stream: The coach's event stream for one turn.
    /// - Returns: The folded transcript. Throws whatever the stream throws.
    public static func collecting(
        _ stream: AsyncThrowingStream<CoachEvent, Error>
    ) async throws -> TurnTranscript {
        var transcript = TurnTranscript()
        for try await event in stream {
            transcript.fold(event)
        }
        return transcript
    }

    /// The reply with surrounding whitespace removed.
    public var trimmedReply: String {
        reply.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Number of whitespace-separated words in the reply.
    public var wordCount: Int {
        reply.split(whereSeparator: \.isWhitespace).count
    }
}
