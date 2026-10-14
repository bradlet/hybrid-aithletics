//
//  StubAICoachService.swift
//  Hybrid AIthletics
//
//  Deterministic AI coach implementation used by SwiftUI previews and unit
//  tests. Returns a canned response without loading any real model, so it
//  is fast, hermetic, and safe to invoke anywhere the real MLX-backed
//  service would be inappropriate.
//

import Foundation
import AICoachCore

/// A stub coach that returns a fixed, human-readable response.
///
/// Use this as the default `@Environment(\.aiCoach)` value so previews do
/// not trigger MLX loading, and in tests that only care about the view
/// layer's wiring rather than actual model output.
struct StubAICoachService: AICoachService {

    /// Default canned narrative returned by every call. Composed to read
    /// plausibly even without any real analysis.
    static let defaultNarrative: String = """
    Based on your last few weeks, your easy days look well-controlled but your \
    tempo sessions have been landing high on the RPE scale. For the coming two \
    weeks, I'd swap Wednesday's interval session for a second easy run, keep \
    the long run but cap it at 90 minutes, and preserve Saturday's tempo at a \
    slightly reduced volume. If your felt-ratings trend back down, we can \
    reintroduce intensity the following week.
    """

    let narrative: String

    init(narrative: String = StubAICoachService.defaultNarrative) {
        self.narrative = narrative
    }

    func suggestAdaptations(_ request: CoachingRequest) async throws -> CoachingResponse {
        CoachingResponse(narrative: narrative)
    }

    /// Phrases that steer the stub toward a particular tool, so previews and
    /// UI tests can drive each branch deterministically without a real model.
    enum ChatTrigger {
        /// Produces a `record_workout` proposal.
        static let record = "record"
        /// Produces a `suggest_schedule_change` proposal.
        static let scheduleChange = "change my plan"
        /// Produces a rejected tool call.
        static let reject = "garble"
    }

    func streamChat(_ request: CoachChatRequest) -> AsyncThrowingStream<CoachEvent, Error> {
        let lastUserTurn = request.messages.last { $0.role == .user }?.text ?? ""
        let events = Self.events(for: lastUserTurn)
        return AsyncThrowingStream { continuation in
            Task {
                for event in events {
                    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
                    continuation.yield(event)
                }
                continuation.finish()
            }
        }
    }

    /// Builds the canned event sequence for a user turn.
    ///
    /// Text is emitted in small chunks so streaming UIs exercise their typing
    /// state, and the last user turn is echoed back so a test can assert which
    /// turn was actually sent.
    private static func events(for userTurn: String) -> [CoachEvent] {
        let lowercased = userTurn.lowercased()
        let today = Calendar.current.startOfDay(for: Date())

        if lowercased.contains(ChatTrigger.reject) {
            return [.rejectedToolCall(reason: "malformed_syntax")]
        }
        if lowercased.contains(ChatTrigger.record) {
            return textChunks("Logging that now — here is what I have.") + [
                .action(.recordWorkout(WorkoutProposal(
                    date: today,
                    exerciseType: .easyRun,
                    distanceMiles: 5.0,
                    durationSeconds: 2700,
                    perceivedExertion: 4,
                    feeling: nil,
                    notes: nil
                )))
            ]
        }
        if lowercased.contains(ChatTrigger.scheduleChange) {
            return textChunks("Here is the change I would make.") + [
                .action(.suggestScheduleChange(ScheduleChangeProposal(
                    date: today,
                    kind: .adjustDistance,
                    distanceMiles: 4.0,
                    rationale: "Your recent RPE suggests backing off slightly."
                )))
            ]
        }
        return textChunks("You asked: \"\(userTurn)\". " + defaultNarrative)
    }

    /// Splits text into 24-character chunks, matching `streamSuggestion`.
    private static func textChunks(_ text: String) -> [CoachEvent] {
        var chunks: [CoachEvent] = []
        var index = text.startIndex
        while index < text.endIndex {
            let end = text.index(index, offsetBy: 24, limitedBy: text.endIndex) ?? text.endIndex
            chunks.append(.textChunk(String(text[index..<end])))
            index = end
        }
        return chunks
    }

    func streamSuggestion(_ request: CoachingRequest) -> AsyncThrowingStream<String, Error> {
        // Yield the canned text in small chunks so that streaming UIs can
        // exercise their typing/progress states against the stub.
        let text = narrative
        return AsyncThrowingStream { continuation in
            Task {
                let chunkSize = 24
                var index = text.startIndex
                while index < text.endIndex {
                    try? await Task.sleep(nanoseconds: 20_000_000) // 20ms
                    let end = text.index(index, offsetBy: chunkSize, limitedBy: text.endIndex) ?? text.endIndex
                    continuation.yield(String(text[index..<end]))
                    index = end
                }
                continuation.finish()
            }
        }
    }
}
