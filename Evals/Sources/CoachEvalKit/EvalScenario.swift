//
//  EvalScenario.swift
//  CoachEvalKit
//
//  One thing we want the coach to get right: a conversation so far, the
//  athlete's next message, and what a good response must satisfy.
//

import Foundation
import AICoachCore

/// A single eval case.
///
/// The model generates exactly one turn — its response to `athleteMessage` —
/// and the `expectations` grade that turn. Earlier turns in `history` are
/// scripted, not generated, so a multi-turn scenario tests one decision at a
/// time instead of compounding the model's earlier mistakes.
public struct EvalScenario: Sendable {
    /// Short identifier used on the command line, e.g. `record-yesterday`.
    public let id: String
    /// Human-readable name for reports.
    public let title: String
    /// What this scenario checks and why it matters.
    public let summary: String
    /// Labels for running a subset with `--tag`, e.g. `record`, `invariant`.
    public let tags: Set<String>
    /// The date the model is told it is.
    public let today: Date
    /// The training snapshot the app would attach, or `nil` for none.
    public let snapshot: CoachingRequest?
    /// Scripted earlier turns, oldest first (`.user` / `.coach` only).
    public let history: [CoachMessage]
    /// The athlete's message the model responds to.
    public let athleteMessage: String
    /// What the response must satisfy.
    public let expectations: [Expectation]

    /// Creates a scenario.
    public init(
        id: String,
        title: String,
        summary: String,
        tags: Set<String> = [],
        today: Date = EvalCalendar.today,
        snapshot: CoachingRequest?,
        history: [CoachMessage] = [],
        athleteMessage: String,
        expectations: [Expectation]
    ) {
        self.id = id
        self.title = title
        self.summary = summary
        self.tags = tags
        self.today = today
        self.snapshot = snapshot
        self.history = history
        self.athleteMessage = athleteMessage
        self.expectations = expectations
    }

    /// The request the app would send for this turn.
    ///
    /// The snapshot rides as `context`, which the prompt builder embeds in the
    /// *first* user turn — where the app put it when the conversation began —
    /// however many turns of `history` follow.
    public func chatRequest() -> CoachChatRequest {
        CoachChatRequest(
            messages: history + [CoachMessage(role: .user, text: athleteMessage)],
            context: snapshot
        )
    }
}
