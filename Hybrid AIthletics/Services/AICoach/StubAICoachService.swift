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
final class StubAICoachService: AICoachService, @unchecked Sendable {

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

    /// Whether the stub pretends its weights are already on disk.
    ///
    /// `false` lets previews and UI tests exercise the pre-download call to
    /// action and the progress bar without touching the network.
    private(set) var isModelCached: Bool

    /// Simulated total download size.
    let approximateDownloadBytes: Int64

    /// How many progress steps a simulated download reports, and how long it
    /// pauses between them.
    private let simulatedSteps: Int
    private let simulatedStepDelay: Duration

    var onDownloadProgress: (@Sendable (AICoachDownloadProgress) -> Void)?

    private var loaded = false

    /// Whether the model is loaded and ready to generate.
    var isModelReady: Bool { loaded }

    init(
        narrative: String = StubAICoachService.defaultNarrative,
        isModelCached: Bool = true,
        approximateDownloadBytes: Int64 = 4_372_000_000,
        simulatedSteps: Int = 10,
        simulatedStepDelay: Duration = .milliseconds(120)
    ) {
        self.narrative = narrative
        self.isModelCached = isModelCached
        self.approximateDownloadBytes = approximateDownloadBytes
        self.simulatedSteps = simulatedSteps
        self.simulatedStepDelay = simulatedStepDelay
        // An already-cached stub is ready as soon as it is loaded; an
        // uncached one has to be "downloaded" first.
        self.loaded = false
    }

    /// Simulates loading, reporting incremental byte progress when the weights
    /// are not yet "cached" so a progress bar can be seen to move.
    func loadModel() async throws {
        guard !loaded else { return }
        if !isModelCached, let onDownloadProgress {
            for step in 1...simulatedSteps {
                try? await Task.sleep(for: simulatedStepDelay)
                let completed = approximateDownloadBytes / Int64(simulatedSteps) * Int64(step)
                onDownloadProgress(
                    AICoachDownloadProgress(
                        completedBytes: min(completed, approximateDownloadBytes),
                        totalBytes: approximateDownloadBytes,
                        // A fixed plausible rate, so the progress card's rate
                        // and time-remaining line renders in previews and UI
                        // tests rather than only against a real network.
                        bytesPerSecond: 12 * 1024 * 1024
                    )
                )
            }
            isModelCached = true
        }
        loaded = true
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
        /// Produces a `plan_strength_day` proposal.
        static let strengthDay = "strength day"
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
        if lowercased.contains(ChatTrigger.strengthDay) {
            return textChunks("Here is a full body day for Friday.") + [
                .action(.planStrengthDay(StrengthDayProposal(
                    weekdayIndex: 5,
                    exercises: [
                        PlannedStrengthExercise(
                            name: "Barbell Back Squat", muscleGroup: .quads,
                            plannedSets: 3, plannedReps: 5
                        ),
                        PlannedStrengthExercise(
                            name: "Barbell Bench Press", muscleGroup: .chest,
                            plannedSets: 3, plannedReps: 8
                        ),
                        PlannedStrengthExercise(
                            name: "Pull-Up", muscleGroup: .back,
                            plannedSets: 3, plannedReps: 8
                        ),
                    ],
                    rationale: "A balanced full body session: legs, chest and back."
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
