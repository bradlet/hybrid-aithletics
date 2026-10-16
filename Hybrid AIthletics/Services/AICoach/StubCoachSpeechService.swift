//
//  StubCoachSpeechService.swift
//  Hybrid AIthletics
//
//  Deterministic speech-to-text implementation used by SwiftUI previews,
//  unit tests, and UI tests. Emits a canned transcript on `start()` so the
//  voice-entry flow is testable without a microphone, a permission prompt,
//  or a live recognizer.
//

import Foundation
import Observation

/// A stub dictation engine that "hears" a fixed phrase.
///
/// Use this as the default `@Environment(\.coachSpeech)` value so previews
/// never touch the microphone, and under `-uiTestSeed` so UI tests can drive
/// the voice-entry flow deterministically.
@MainActor
@Observable
final class StubCoachSpeechService: CoachSpeechService {

    /// What the stub hears by default: a plausible coaching question, so UI
    /// tests read like the real flow.
    static let defaultTranscript = "How should I adjust my training this week?"

    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var errorMessage: String?

    /// When set, `start()` surfaces this instead of recording — the denial
    /// path, exercised without a real Settings trip.
    var cannedError: String?

    /// The phrase `start()` reports having heard.
    let cannedTranscript: String

    nonisolated init(transcript: String = StubCoachSpeechService.defaultTranscript) {
        self.cannedTranscript = transcript
    }

    /// Emits the canned transcript immediately and holds the recording state
    /// until `stop()`, so the composer renders mid-dictation in tests.
    func start() async {
        guard !isRecording else { return }
        errorMessage = nil
        if let cannedError {
            errorMessage = cannedError
            return
        }
        transcript = cannedTranscript
        isRecording = true
    }

    func stop() {
        isRecording = false
    }

    func reset() {
        transcript = ""
        errorMessage = nil
    }
}
