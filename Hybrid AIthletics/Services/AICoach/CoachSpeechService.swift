//
//  CoachSpeechService.swift
//  Hybrid AIthletics
//
//  Speech-to-text for the coach composer, plus the pure merge of dictated
//  text into whatever the athlete already typed.
//

import Foundation

/// Dictation engine behind the coach composer's mic button and the Home
/// tab's voice entry point.
///
/// Mirrors the `AICoachService` split: the live implementation wraps
/// SFSpeechRecognizer, the stub keeps previews and UI tests deterministic.
/// Injected via `@Environment(\.coachSpeech)`.
@MainActor
protocol CoachSpeechService: AnyObject {
    /// The running transcription for the current (or last) session.
    var transcript: String { get }
    /// Whether the microphone is currently capturing.
    var isRecording: Bool { get }
    /// A user-facing reason dictation could not start or stopped early.
    var errorMessage: String? { get }
    /// Requests authorization and starts capturing, streaming partial results
    /// into `transcript`. A refusal or hardware failure is reported in
    /// `errorMessage` rather than thrown — the composer stays usable for
    /// typing either way.
    func start() async
    /// Stops capturing, keeping whatever was transcribed for review.
    func stop()
    /// Clears the transcript and any error, arming the next session.
    func reset()
}

/// Pure merge of dictated text with what was already in the composer.
enum VoiceDraft {
    /// Appends the live transcript to the draft as it stood when recording
    /// began. Exactly one space joins them; a blank transcript returns the
    /// prefix untouched so starting the mic never rewrites typed text.
    static func compose(prefix: String, transcript: String) -> String {
        let spoken = transcript.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !spoken.isEmpty else { return prefix }
        let typed = prefix.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !typed.isEmpty else { return spoken }
        return typed + " " + spoken
    }
}
