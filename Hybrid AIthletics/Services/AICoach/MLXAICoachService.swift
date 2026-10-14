//
//  MLXAICoachService.swift
//  Hybrid AIthletics
//
//  Production AI coach backed by Gemma 3 4B running on-device via MLX-Swift.
//
//  The model is downloaded from Hugging Face on first use and cached locally
//  for offline access. The real implementation compiles when the `MLXLLM`
//  module is available (mlx-swift-lm SPM package, >= 3.32.3). The #else
//  branches throw AICoachError.notImplemented so the app stays launchable on
//  hosts where the package has not been resolved.
//
//  Weight download and tokenizer loading are supplied by MLXModelLoading.swift:
//  mlx-swift-lm 3.0 removed its bundled Hugging Face Hub integration.

import Foundation
import AICoachCore

#if canImport(MLXLLM)
import MLX
import MLXLLM
import MLXLMCommon
#endif

/// Coaching service backed by Gemma 3 4B downloaded from Hugging Face and run
/// on-device via MLX-Swift.
///
/// The model is downloaded lazily on the first call and cached in the app's
/// caches directory. Subsequent launches load the cached copy (works offline).
/// Callers should create a single shared instance at the app root and inject
/// it via `@Environment(\.aiCoach)`.
final class MLXAICoachService: AICoachService, @unchecked Sendable {

    /// Hugging Face model ID — downloaded on first use, cached locally.
    static let modelID = "mlx-community/gemma-3-4b-it-qat-4bit"

    // MARK: - Generation parameters
    //
    // All generation parameters are centralized in AICoachCore.GenerationConfig
    // so that the eval CLI and the live app use identical settings. Override
    // `generationConfig` here only for temporary local experiments.

    /// Generation parameters — reads from AICoachCore's single source of truth.
    var generationConfig = GenerationConfig.production

    /// Optional callback invoked with download progress (0.0–1.0) during
    /// first-time model weight download. Set by the presenting view before
    /// triggering `loadModel()`.
    var onDownloadProgress: (@Sendable (Double) -> Void)?

    #if canImport(MLXLLM)
    // `toolCallFormat` is what lets the runtime's GemmaFunctionParser recognize
    // this model's `call:name{...}` tool-call syntax. Switching to a Gemma 4
    // checkpoint means switching this to `.gemma4`.
    private let configuration = ModelConfiguration(
        id: MLXAICoachService.modelID,
        extraEOSTokens: ["<end_of_turn>"],
        toolCallFormat: .gemma
    )

    /// Cached model container — populated by `loadModel()` or lazily on first
    /// generation call. Avoids re-downloading on every request.
    private var cachedContainer: ModelContainer?
    #endif

    /// Whether the model weights are already cached on disk.
    var isModelCached: Bool {
        #if canImport(MLXLLM)
        return isHuggingFaceRepoCached(Self.modelID)
        #else
        return false
        #endif
    }

    /// Whether the model is loaded into memory and ready for generation.
    var isModelReady: Bool {
        #if canImport(MLXLLM)
        return cachedContainer != nil
        #else
        return false
        #endif
    }

    /// Downloads (if needed) and loads the model into memory without running
    /// generation. Sets `isModelReady` to `true` on success.
    func loadModel() async throws {
        #if canImport(MLXLLM)
        guard cachedContainer == nil else { return }
        // Cap MLX's GPU buffer cache so iOS jetsam doesn't kill the app during
        // generation. Without this, intermediate inference buffers accumulate
        // until peak RSS crosses the per-process memory limit and the OS
        // SIGKILLs us mid-token. 20 MB matches MLX's iOS guidance.
        MLX.Memory.cacheLimit = 20 * 1024 * 1024
        let progressHandler = onDownloadProgress
        // mlx-swift-lm 3.x dropped its bundled Hub integration: the caller now
        // supplies how weights are fetched and how the tokenizer is read.
        // See MLXModelLoading.swift.
        cachedContainer = try await LLMModelFactory.shared.loadContainer(
            from: HuggingFaceDownloader(),
            using: HuggingFaceTokenizerLoader(),
            configuration: configuration
        ) { progress in
            progressHandler?(progress.fractionCompleted)
        }
        #else
        throw AICoachError.notImplemented(message:
            "MLXAICoachService requires the MLX-Swift package."
        )
        #endif
    }

    func suggestAdaptations(_ request: CoachingRequest) async throws -> CoachingResponse {
        #if canImport(MLXLLM)
        let text = try await generate(request: request)
        return CoachingResponse(narrative: text)
        #else
        throw AICoachError.notImplemented(message:
            "MLXAICoachService requires the MLX-Swift package to be added to the " +
            "project. See the file header for wiring instructions."
        )
        #endif
    }

    func streamSuggestion(_ request: CoachingRequest) -> AsyncThrowingStream<String, Error> {
        #if canImport(MLXLLM)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.generateStreaming(request: request) { chunk in
                        continuation.yield(chunk)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        #else
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: AICoachError.notImplemented(message:
                "MLXAICoachService requires the MLX-Swift package. See file header."
            ))
        }
        #endif
    }

    func streamChat(_ request: CoachChatRequest) -> AsyncThrowingStream<CoachEvent, Error> {
        #if canImport(MLXLLM)
        return AsyncThrowingStream { continuation in
            Task {
                do {
                    try await self.generateStreamingChat(request: request) { event in
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
        }
        #else
        return AsyncThrowingStream { continuation in
            continuation.finish(throwing: AICoachError.notImplemented(message:
                "MLXAICoachService requires the MLX-Swift package. See file header."
            ))
        }
        #endif
    }

    // MARK: - MLX-backed generation (active once the SPM dep is added)

    #if canImport(MLXLLM)

    /// Returns the cached container or loads it on demand.
    private func getContainer() async throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        try await loadModel()
        return cachedContainer!
    }

    /// Returns configured generation parameters from `GenerationConfig`.
    private func makeParameters() -> GenerateParameters {
        makeParameters(generationConfig)
    }

    /// Returns generation parameters for an explicit configuration, so the
    /// conversational path can use `GenerationConfig.chat` without mutating
    /// the service's one-shot default.
    private func makeParameters(_ config: GenerationConfig) -> GenerateParameters {
        GenerateParameters(
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            topP: config.topP,
            repetitionPenalty: config.repetitionPenalty,
            repetitionContextSize: config.repetitionContextSize
        )
    }

    /// Loads (or downloads) the model and runs generation to completion.
    ///
    /// Uses the non-deprecated `AsyncStream<Generation>` overload of
    /// `MLXLMCommon.generate` so that detokenization goes through MLX's
    /// `NaiveStreamingDetokenizer`. The old `didGenerate: ([Int]) -> ...`
    /// overload passes a cumulative token array on every call — misreading
    /// it as a delta produces quadratic growth, premature stop, and garbled
    /// output.
    private func generate(request: CoachingRequest) async throws -> String {
        let container = try await getContainer()
        let parameters = makeParameters()
        // Capture only `Sendable` values (`request`, `parameters`) in the
        // perform closure. `UserInput` is non-Sendable, so build it inside
        // the closure rather than capturing it from the outer scope.
        return try await container.perform { context in
            let userInput = UserInput(chat: [
                .system(AICoachPromptBuilder.systemPreamble),
                .user(AICoachPromptBuilder.buildUserContent(for: request)),
            ])
            let input = try await context.processor.prepare(input: userInput)
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context
            )
            var output = ""
            for await event in stream {
                if case .chunk(let text) = event {
                    output += text
                }
            }
            return output
        }
    }

    /// Conversational generation with tools enabled.
    ///
    /// Yields `CoachEvent`s so the caller never has to know about MLX's
    /// `Generation` type. A tool call that fails validation becomes
    /// `.rejectedToolCall` rather than throwing: one bad call should not
    /// discard the turn's text, and the athlete is better served by "the coach
    /// garbled that" than by silence.
    private func generateStreamingChat(
        request: CoachChatRequest,
        onEvent: @escaping @Sendable (CoachEvent) -> Void
    ) async throws {
        let container = try await getContainer()
        let parameters = makeParameters(.chat)
        let turns = AICoachPromptBuilder.buildChatTurns(for: request)
        let tools = CoachToolSchemas.all
        // As in `generateStreaming`, the non-Sendable `UserInput` is built
        // inside the closure so it isn't captured across the actor hop.
        try await container.perform { context in
            let userInput = UserInput(
                chat: turns.map(Self.chatMessage(from:)),
                tools: tools
            )
            let input = try await context.processor.prepare(input: userInput)
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context,
                tools: tools
            )
            for await event in stream {
                switch event {
                case .chunk(let text):
                    onEvent(.textChunk(text))
                case .toolCall(let call):
                    onEvent(Self.coachEvent(from: call))
                case .rejectedToolCall(let rejection):
                    onEvent(.rejectedToolCall(reason: rejection.reason.rawValue))
                default:
                    // `.info` carries token counts and timings, and the enum is
                    // not frozen — ignore anything that isn't content.
                    break
                }
            }
        }
    }

    /// Maps a conversation turn to the runtime's chat message type.
    private static func chatMessage(from message: CoachMessage) -> Chat.Message {
        switch message.role {
        case .system: .system(message.text)
        case .user: .user(message.text)
        case .coach: .assistant(message.text)
        }
    }

    /// Decodes and validates a raw tool call into a coach event.
    private static func coachEvent(from call: ToolCall) -> CoachEvent {
        let arguments = call.function.arguments.mapValues(\.anyValue)
        do {
            return .action(
                try CoachToolDecoder.decode(name: call.function.name, arguments: arguments)
            )
        } catch let error as CoachToolDecodeError {
            return .rejectedToolCall(reason: error.localizedDescription)
        } catch {
            return .rejectedToolCall(reason: error.localizedDescription)
        }
    }

    /// Streaming variant — yields decoded text deltas to `onChunk` as they are generated.
    private func generateStreaming(
        request: CoachingRequest,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws {
        let container = try await getContainer()
        let parameters = makeParameters()
        // As in `generate(request:)`, construct the non-Sendable `UserInput`
        // inside the perform closure so it isn't captured across actor hops.
        try await container.perform { context in
            let userInput = UserInput(chat: [
                .system(AICoachPromptBuilder.systemPreamble),
                .user(AICoachPromptBuilder.buildUserContent(for: request)),
            ])
            let input = try await context.processor.prepare(input: userInput)
            let stream = try MLXLMCommon.generate(
                input: input,
                parameters: parameters,
                context: context
            )
            for await event in stream {
                if case .chunk(let text) = event {
                    onChunk(text)
                }
            }
        }
    }

    #endif
}
