//
//  CoachTurnGenerator.swift
//  CoachEvalKit
//
//  The seam between the eval runner and whatever produces coach turns: the
//  real model on Metal (in the CoachEval executable) or a scripted double
//  (in tests).
//

import Foundation
import AICoachCore

/// Something that can produce one coach turn for a request.
///
/// The runner only knows this protocol, which is what lets every piece of the
/// suite except the model itself be unit-tested in milliseconds.
public protocol CoachTurnGenerator: Sendable {
    /// Identifies the model in saved results, e.g. a Hugging Face repo id.
    var modelID: String { get }

    /// Generates the coach's next turn.
    /// - Parameters:
    ///   - request: The conversation so far plus the optional snapshot.
    ///   - today: The date the model is told it is.
    ///   - config: Sampling parameters.
    /// - Returns: The folded turn, with stats when available.
    func respond(
        to request: CoachChatRequest,
        today: Date,
        config: GenerationConfig
    ) async throws -> TurnTranscript
}

/// A generator that replays canned events — for tests and dry runs.
///
/// An `actor` because it counts calls: the runner may call it from several
/// tasks, and actor isolation makes that counter safe without a lock.
public actor ScriptedGenerator: CoachTurnGenerator {

    /// Shown in saved results.
    public nonisolated let modelID: String

    /// Produces the events for a call, given the request and the call's
    /// zero-based index (so successive samples can differ).
    private let script: @Sendable (CoachChatRequest, Int) throws -> [CoachEvent]

    /// How many turns have been generated so far.
    public private(set) var callCount = 0

    /// Creates a generator from a script.
    public init(
        modelID: String = "scripted",
        script: @escaping @Sendable (CoachChatRequest, Int) throws -> [CoachEvent]
    ) {
        self.modelID = modelID
        self.script = script
    }

    /// Creates a generator that always returns the same events.
    public init(modelID: String = "scripted", always events: [CoachEvent]) {
        self.init(modelID: modelID) { _, _ in events }
    }

    public func respond(
        to request: CoachChatRequest,
        today: Date,
        config: GenerationConfig
    ) async throws -> TurnTranscript {
        let index = callCount
        callCount += 1
        return TurnTranscript.folding(try script(request, index))
    }
}
