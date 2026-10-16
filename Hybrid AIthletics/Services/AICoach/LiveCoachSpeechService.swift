//
//  LiveCoachSpeechService.swift
//  Hybrid AIthletics
//
//  Production speech-to-text for the coach composer, built on
//  SFSpeechRecognizer + AVAudioEngine.
//

import Foundation
import Observation
import Speech
import AVFoundation

/// Live dictation into the coach composer.
///
/// Uses the same system speech recognition that powers keyboard dictation:
/// partial results stream into `transcript` as the athlete talks, so the
/// composer fills live. On-device recognition is required where the device
/// supports it, matching the coach's own privacy bar.
@MainActor
@Observable
final class LiveCoachSpeechService: CoachSpeechService {

    private(set) var transcript = ""
    private(set) var isRecording = false
    private(set) var errorMessage: String?

    /// Locale-default recognizer. Nil on configurations without one.
    private let recognizer: SFSpeechRecognizer?

    private var audioEngine: AVAudioEngine?
    private var request: SFSpeechAudioBufferRecognitionRequest?
    private var recognitionTask: SFSpeechRecognitionTask?

    nonisolated init(recognizer: SFSpeechRecognizer? = SFSpeechRecognizer()) {
        self.recognizer = recognizer
    }

    /// Requests both authorizations, then starts capturing. Refusals land in
    /// `errorMessage` with a Settings pointer rather than throwing.
    func start() async {
        guard !isRecording else { return }
        errorMessage = nil

        let speechStatus = await Self.requestSpeechAuthorization()
        guard speechStatus == .authorized else {
            errorMessage = "Speech recognition is off — enable it in Settings to dictate to your coach."
            return
        }
        guard await AVAudioApplication.requestRecordPermission() else {
            errorMessage = "Microphone access is off — enable it in Settings to dictate to your coach."
            return
        }
        guard let recognizer, recognizer.isAvailable else {
            errorMessage = "Speech recognition isn't available right now."
            return
        }

        do {
            try beginCapture(using: recognizer)
            isRecording = true
        } catch {
            tearDownCapture()
            errorMessage = "Couldn't start the microphone: \(error.localizedDescription)"
        }
    }

    /// Ends capture. Whatever has been transcribed so far stays in
    /// `transcript` — the athlete reviews and sends it themselves.
    func stop() {
        guard isRecording else { return }
        request?.endAudio()
        tearDownCapture()
    }

    func reset() {
        transcript = ""
        errorMessage = nil
    }

    // MARK: - Capture pipeline

    /// Wires mic → recognition request → recognition task and starts the
    /// engine. Throws before any state is published, so a failure leaves the
    /// service idle.
    private func beginCapture(using recognizer: SFSpeechRecognizer) throws {
        let session = AVAudioSession.sharedInstance()
        try session.setCategory(.record, mode: .measurement, options: .duckOthers)
        try session.setActive(true, options: .notifyOthersOnDeactivation)

        let engine = AVAudioEngine()
        let request = SFSpeechAudioBufferRecognitionRequest()
        request.shouldReportPartialResults = true
        if recognizer.supportsOnDeviceRecognition {
            request.requiresOnDeviceRecognition = true
        }

        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        input.installTap(onBus: 0, bufferSize: 1024, format: format) { buffer, _ in
            request.append(buffer)
        }
        engine.prepare()
        try engine.start()

        recognitionTask = recognizer.recognitionTask(with: request) { [weak self] result, error in
            Task { @MainActor [weak self] in
                self?.handle(result: result, error: error)
            }
        }

        audioEngine = engine
        self.request = request
    }

    /// Folds a recognition callback into published state. Partial results
    /// stream into `transcript`; a final result or an error ends the session.
    /// An error after usable text arrived is swallowed — the transcript is
    /// already in the composer, and flagging it would read as a failure of
    /// something that worked. iOS ends a long (~1 minute) session this way.
    private func handle(result: SFSpeechRecognitionResult?, error: Error?) {
        if let result {
            transcript = result.bestTranscription.formattedString
        }
        guard error != nil || (result?.isFinal ?? false) else { return }
        if error != nil, isRecording, transcript.isEmpty {
            errorMessage = "Didn't catch that — try dictating again."
        }
        tearDownCapture()
    }

    /// Stops the engine and releases the pipeline. Idempotent: cancelling
    /// the task re-enters through `handle`.
    private func tearDownCapture() {
        audioEngine?.stop()
        audioEngine?.inputNode.removeTap(onBus: 0)
        recognitionTask?.cancel()
        recognitionTask = nil
        request = nil
        audioEngine = nil
        isRecording = false
        try? AVAudioSession.sharedInstance().setActive(false, options: .notifyOthersOnDeactivation)
    }

    /// Bridges the callback-based authorization API into async.
    private static func requestSpeechAuthorization() async -> SFSpeechRecognizerAuthorizationStatus {
        await withCheckedContinuation { continuation in
            SFSpeechRecognizer.requestAuthorization { status in
                continuation.resume(returning: status)
            }
        }
    }
}
