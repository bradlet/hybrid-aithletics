//
//  CoachSpeechEnvironment.swift
//  Hybrid AIthletics
//
//  SwiftUI environment key that injects the shared speech-to-text service.
//

import SwiftUI

/// Environment key for the shared `CoachSpeechService` instance.
private struct CoachSpeechKey: EnvironmentKey {
    /// Default is the stub so previews never touch the microphone.
    static let defaultValue: CoachSpeechService = StubCoachSpeechService()
}

extension EnvironmentValues {
    /// The active speech service. Defaults to `StubCoachSpeechService`; the
    /// app root injects the live recognizer outside UI tests.
    var coachSpeech: CoachSpeechService {
        get { self[CoachSpeechKey.self] }
        set { self[CoachSpeechKey.self] = newValue }
    }
}
