//
//  CoachChat.swift
//  AICoachCore
//
//  Value types for a multi-turn coaching conversation. Separate from the
//  one-shot `CoachingRequest` / `CoachingResponse` pair, which remains the
//  non-conversational surface used by the eval tooling.
//

import Foundation

/// Who authored a turn in a coaching conversation.
public enum CoachRole: String, Codable, Sendable {
    /// Framing instructions for the model. Added by the prompt builder, never
    /// by a caller.
    case system
    /// The athlete.
    case user
    /// The model.
    case coach
}

/// One turn in a coaching conversation.
///
/// `text` is mutable because streaming generation accumulates into the
/// trailing coach turn as chunks arrive.
public struct CoachMessage: Identifiable, Equatable, Sendable {
    public let id: UUID
    public let role: CoachRole
    public var text: String

    public init(id: UUID = UUID(), role: CoachRole, text: String = "") {
        self.id = id
        self.role = role
        self.text = text
    }
}

/// A request for the next coach turn in a conversation.
///
/// Conforms to `Identifiable` so it can drive SwiftUI presentation directly,
/// matching `CoachingRequest`.
public struct CoachChatRequest: Identifiable, Sendable {
    public let id: UUID
    /// The conversation so far, oldest first. Contains no `.system` turn —
    /// `AICoachPromptBuilder.buildChatTurns(for:)` adds that.
    public let messages: [CoachMessage]
    /// Training data to embed in the **first** user turn, or `nil` to send the
    /// transcript alone.
    ///
    /// The app attaches a snapshot once per conversation: re-sending it on every
    /// turn would spend a large share of a 4B model's context window restating
    /// data the transcript already carries.
    public let context: CoachingRequest?

    public init(
        id: UUID = UUID(),
        messages: [CoachMessage],
        context: CoachingRequest? = nil
    ) {
        self.id = id
        self.messages = messages
        self.context = context
    }
}

/// An incremental event produced while the coach generates a turn.
///
/// Mirrors the cases of the model runtime's own generation stream so the app
/// layer can pattern-match a response without importing MLX.
public enum CoachEvent: Equatable, Sendable {
    /// A fragment of conversational text.
    case textChunk(String)
    /// A decoded, validated tool call.
    case action(CoachAction)
    /// The model emitted something tool-call shaped that could not be used.
    ///
    /// Surfaced rather than swallowed: a small model's malformed call would
    /// otherwise be indistinguishable from the coach having nothing to say.
    case rejectedToolCall(reason: String)
}
