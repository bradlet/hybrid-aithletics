//
//  MLXAICoachService.swift
//  Hybrid AIthletics
//
//  Production AI coach backed by Gemma 4 E2B running on-device via MLX-Swift.
//
//  The model is downloaded from Hugging Face when the athlete opts in (see
//  CoachChatStore.downloadModel) and cached locally for offline access.
//
//  Everything that talks to the model — the model preset, weight download,
//  tokenizer loading, and the generate → tool-call → `CoachEvent` loop — lives
//  in the AICoachRuntime package (`CoachRuntime`), which the `Evals/` CLI also
//  uses. This type adapts it to the app's `AICoachService` protocol.
//

import Foundation
import AICoachCore
import AICoachRuntime

/// Coaching service backed by Gemma 4 E2B downloaded from Hugging Face and run
/// on-device via MLX-Swift.
///
/// The weights are downloaded by `loadModel()` — which `CoachChatStore` only
/// calls for a missing model after the athlete taps Download — and cached in
/// `HubApi`'s download directory. Subsequent launches load the cached copy
/// (works offline).
/// Callers should create a single shared instance at the app root and inject
/// it via `@Environment(\.aiCoach)`.
final class MLXAICoachService: AICoachService, @unchecked Sendable {

    /// Hugging Face model ID — downloaded on first use, cached locally.
    /// Defined by `CoachModelPreset.production`; see there for why this repo.
    static let modelID = CoachModelPreset.production.id

    // MARK: - Generation parameters
    //
    // All generation parameters are centralized in AICoachCore.GenerationConfig
    // so that the eval CLI and the live app use identical settings. Override
    // `generationConfig` here only for temporary local experiments.

    /// Generation parameters for the one-shot path — reads from AICoachCore's
    /// single source of truth. The conversation always uses `.chat`.
    var generationConfig = GenerationConfig.production

    /// Optional callback invoked with byte-level download progress during the
    /// first-time model weight download. Set before triggering `loadModel()`.
    var onDownloadProgress: (@Sendable (AICoachDownloadProgress) -> Void)?

    /// Approximate download size of the model, for the pre-download call to
    /// action. Hardcoded on the preset because the real figure needs a network
    /// round-trip, and the CTA has to render before any network use; the
    /// downloader reports exact bytes once it starts.
    var approximateDownloadBytes: Int64 { runtime.preset.approximateDownloadBytes }

    /// The shared model runtime. MLX's GPU buffer cache is capped at 20 MB so
    /// iOS jetsam doesn't kill the app during generation: without it,
    /// intermediate inference buffers accumulate until peak RSS crosses the
    /// per-process memory limit and the OS SIGKILLs us mid-token.
    private let runtime = CoachRuntime(preset: .production, memoryCacheLimit: 20 * 1024 * 1024)

    /// Whether the model weights are already cached on disk.
    var isModelCached: Bool { runtime.isCached }

    /// Whether the model is loaded into memory and ready for generation.
    var isModelReady: Bool { runtime.isReady }

    /// Downloads (if needed) and loads the model into memory without running
    /// generation. Sets `isModelReady` to `true` on success.
    func loadModel() async throws {
        let progressHandler = onDownloadProgress
        try await runtime.load { progress in
            progressHandler?(
                AICoachDownloadProgress(
                    completedBytes: progress.completedUnitCount,
                    totalBytes: progress.totalUnitCount,
                    bytesPerSecond: progress.userInfo[.throughputKey] as? Double
                )
            )
        }
    }

    /// Generates a complete one-shot coaching response.
    func suggestAdaptations(_ request: CoachingRequest) async throws -> CoachingResponse {
        var text = ""
        for try await chunk in streamSuggestion(request) {
            text += chunk
        }
        return CoachingResponse(narrative: text)
    }

    /// Streams a one-shot coaching response as text deltas.
    func streamSuggestion(_ request: CoachingRequest) -> AsyncThrowingStream<String, Error> {
        runtime.streamText(
            system: AICoachPromptBuilder.systemPreamble,
            user: AICoachPromptBuilder.buildUserContent(for: request),
            config: generationConfig
        )
    }

    /// Streams the coach's next conversational turn, tools enabled.
    ///
    /// "Today" is resolved per turn, not per conversation: the model has no
    /// clock, so it has to be stated in the system turn and in every date
    /// argument's description or the model fills dates in from an example.
    func streamChat(_ request: CoachChatRequest) -> AsyncThrowingStream<CoachEvent, Error> {
        runtime.streamChat(request, today: Date(), config: .chat)
    }
}
