//
//  AICoachService.swift
//  Hybrid AIthletics
//
//  Protocol abstraction over the on-device coaching model so that the
//  rest of the app never directly depends on MLX (or any specific runtime).
//  Implementations include StubAICoachService (used in previews and tests)
//  and MLXAICoachService (production, backed by Gemma 3 4B).
//

import Foundation
import AICoachCore

/// Byte-level progress for the coach model download.
///
/// Carries bytes rather than a bare fraction so the UI can show real amounts
/// ("1.2 GB of 4.4 GB"), and so progress can be weighted by size. The model
/// repository is one 4.3 GB weights file beside nine files totalling ~33 MB, so
/// a file-count-weighted bar reaches 90% within seconds and then appears stuck
/// for the entire real download.
struct AICoachDownloadProgress: Equatable, Sendable {
    /// Bytes present on disk so far.
    var completedBytes: Int64
    /// Total bytes expected, or 0 when not yet known.
    var totalBytes: Int64

    /// Completed fraction in `0...1`, or `nil` when the total isn't known yet.
    var fraction: Double? {
        guard totalBytes > 0 else { return nil }
        return min(max(Double(completedBytes) / Double(totalBytes), 0), 1)
    }
}

/// A service that produces coaching suggestions for an athlete's training plan.
///
/// Implementations are expected to be cheap to construct but may perform
/// expensive work (e.g. loading model weights) lazily on first invocation.
/// All operations are asynchronous and cancellable via Swift concurrency.
protocol AICoachService: Sendable {
    /// Returns a single coaching response for the given request.
    /// - Parameter request: Recent workouts + upcoming exercises.
    /// - Returns: The coach's full response once generation finishes.
    func suggestAdaptations(_ request: CoachingRequest) async throws -> CoachingResponse

    /// Streams the coach's response as it is generated, token by token
    /// (or chunk by chunk, depending on the backing runtime).
    /// - Parameter request: Recent workouts + upcoming exercises.
    /// - Returns: An async stream yielding incremental text fragments.
    func streamSuggestion(_ request: CoachingRequest) -> AsyncThrowingStream<String, Error>

    /// Streams the coach's next turn in a multi-turn conversation.
    ///
    /// Unlike `streamSuggestion`, the response may include tool calls, so the
    /// stream yields `CoachEvent` values rather than plain text.
    /// - Parameter request: The conversation so far, plus optional training context.
    /// - Returns: An async stream of text chunks, decoded actions, and rejections.
    func streamChat(_ request: CoachChatRequest) -> AsyncThrowingStream<CoachEvent, Error>

    /// Whether the model weights are already cached on disk.
    /// Returns `true` by default (stubs and test doubles always "have" their model).
    var isModelCached: Bool { get }

    /// Whether the model is loaded into memory and ready for generation.
    /// Returns `true` by default (stubs are always ready).
    var isModelReady: Bool { get }

    /// Downloads and loads the model into memory without running generation.
    /// Call this to pre-warm the model so that `isModelReady` becomes `true`.
    func loadModel() async throws

    /// Optional callback invoked with byte-level progress during the
    /// first-time model weight download. Set this before triggering
    /// `loadModel()` to drive a progress bar.
    var onDownloadProgress: (@Sendable (AICoachDownloadProgress) -> Void)? { get set }

    /// Approximate size of the model download, for the pre-download call to
    /// action. `0` when unknown.
    var approximateDownloadBytes: Int64 { get }
}

extension AICoachService {
    var isModelCached: Bool { true }
    var isModelReady: Bool { true }
    func loadModel() async throws { }
    var onDownloadProgress: (@Sendable (AICoachDownloadProgress) -> Void)? {
        get { nil }
        set { }
    }
    var approximateDownloadBytes: Int64 { 0 }
}

/// Errors that can be surfaced by an `AICoachService` implementation.
enum AICoachError: Error, LocalizedError {
    /// The underlying model could not be located or loaded from disk.
    case modelNotLoaded
    /// Generation failed for an implementation-specific reason.
    case generationFailed(underlying: Error)
    /// The model download failed (e.g. no internet on first launch).
    case downloadFailed(underlying: Error)
    /// The implementation has not yet been wired up (e.g. MLX dependency missing).
    case notImplemented(message: String)

    var errorDescription: String? {
        switch self {
        case .modelNotLoaded:
            return "The coaching model could not be loaded."
        case .generationFailed(let underlying):
            return "Coach generation failed: \(underlying.localizedDescription)"
        case .downloadFailed:
            return "Could not download the coaching model. Please check your internet connection and try again."
        case .notImplemented(let message):
            return message
        }
    }
}
