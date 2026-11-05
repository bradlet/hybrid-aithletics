//
//  CoachRuntime.swift
//  AICoachRuntime
//
//  Loads the coach's model and runs generation through MLX-Swift. The one
//  place the coach talks to the model: the iOS app's `MLXAICoachService`
//  forwards here, and so does the `Evals/` CLI, so an eval exercises exactly
//  the prompt assembly, tool wiring, and tool-call decoding the app ships.
//
//  Weight download and tokenizer loading come from ModelLoading.swift:
//  mlx-swift-lm 3.0 removed its bundled Hugging Face Hub integration.
//

import Foundation
import AICoachCore

#if canImport(MLXLLM)
import MLX
import MLXLLM
import MLXLMCommon
#endif

/// Errors raised by `CoachRuntime` itself, as opposed to the model runtime.
public enum CoachRuntimeError: Error, LocalizedError {
    /// The MLX packages were not available when this was compiled.
    case runtimeUnavailable
    /// The preset names a tool-call dialect this mlx-swift-lm doesn't know.
    case unknownToolCallFormat(String)

    public var errorDescription: String? {
        switch self {
        case .runtimeUnavailable:
            return "The coach runtime requires the MLX-Swift packages."
        case .unknownToolCallFormat(let format):
            return "Unknown tool-call format \"\(format)\" for this version of mlx-swift-lm."
        }
    }
}

/// The on-device model behind the coach.
///
/// Holds one loaded model and generates from it. Construct one per process and
/// keep it: loading reads several gigabytes into memory.
///
/// Thread-safety mirrors the app's previous `MLXAICoachService`: the cached
/// container is set once by `load` and then only read, and all generation runs
/// inside `ModelContainer.perform`, which serializes access to the model.
public final class CoachRuntime: @unchecked Sendable {

    /// The model this runtime loads.
    public let preset: CoachModelPreset

    /// Cap on MLX's GPU buffer cache in bytes, or `nil` to leave MLX's default.
    ///
    /// iOS needs a small cap (the app passes 20 MB, MLX's iOS guidance) or
    /// intermediate inference buffers accumulate until jetsam SIGKILLs the app
    /// mid-token. A Mac has the memory to leave it alone.
    public let memoryCacheLimit: Int?

    #if canImport(MLXLLM)
    /// Populated by `load(progress:)`, or lazily on first generation.
    private var cachedContainer: ModelContainer?
    #endif

    /// Creates a runtime. Loads nothing until `load(progress:)` or the first
    /// generation call.
    /// - Parameters:
    ///   - preset: The model to run.
    ///   - memoryCacheLimit: GPU buffer cache cap in bytes; `nil` for MLX's default.
    public init(preset: CoachModelPreset = .production, memoryCacheLimit: Int? = nil) {
        self.preset = preset
        self.memoryCacheLimit = memoryCacheLimit
    }

    /// Whether the model's weights are fully downloaded.
    public var isCached: Bool {
        #if canImport(MLXLLM)
        return isHuggingFaceRepoCached(preset.id)
        #else
        return false
        #endif
    }

    /// Whether the model is loaded into memory and ready to generate.
    public var isReady: Bool {
        #if canImport(MLXLLM)
        return cachedContainer != nil
        #else
        return false
        #endif
    }

    /// Downloads the weights if they are missing, then loads the model.
    ///
    /// A no-op once loaded. With the weights cached this needs no network.
    /// - Parameter progress: Byte-weighted download progress. The `Progress`
    ///   carries a smoothed bytes-per-second rate under `.throughputKey`.
    public func load(progress: (@Sendable (Progress) -> Void)? = nil) async throws {
        #if canImport(MLXLLM)
        guard cachedContainer == nil else { return }
        if let memoryCacheLimit {
            MLX.Memory.cacheLimit = memoryCacheLimit
        }
        guard let format = ToolCallFormat(rawValue: preset.toolCallFormat) else {
            throw CoachRuntimeError.unknownToolCallFormat(preset.toolCallFormat)
        }
        // `toolCallFormat` is what lets the runtime's tool-call parser recognize
        // the model's call syntax; `extraEOSTokens` is what stops generation at
        // the end of the turn. Both are per model family — see the preset.
        let configuration = ModelConfiguration(
            id: preset.id,
            extraEOSTokens: preset.extraEOSTokens,
            toolCallFormat: format
        )
        cachedContainer = try await LLMModelFactory.shared.loadContainer(
            from: HuggingFaceDownloader(),
            using: HuggingFaceTokenizerLoader(),
            configuration: configuration
        ) { value in
            progress?(value)
        }
        #else
        throw CoachRuntimeError.runtimeUnavailable
        #endif
    }

    /// Streams the coach's next turn in a conversation, with tools enabled.
    ///
    /// Prompt assembly is `AICoachPromptBuilder.buildChatTurns(for:today:)` and
    /// the tools are `CoachToolSchemas.all(today:)` — both from AICoachCore — so
    /// what reaches the model is what `inspect` prints.
    /// - Parameters:
    ///   - request: The conversation so far, plus the optional training snapshot.
    ///   - today: The date the model is told it is. The model has no clock, so
    ///     this anchors every relative date ("yesterday") it resolves. The app
    ///     passes `Date()`; evals pin it so scenarios are reproducible.
    ///   - config: Sampling parameters.
    ///   - onStats: Called once with token counts and timings when generation ends.
    /// - Returns: Text chunks, decoded actions, and rejected calls, in order.
    public func streamChat(
        _ request: CoachChatRequest,
        today: Date,
        config: GenerationConfig = .chat,
        onStats: (@Sendable (GenerationStats) -> Void)? = nil
    ) -> AsyncThrowingStream<CoachEvent, Error> {
        #if canImport(MLXLLM)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.generateChat(
                        request: request, today: today, config: config, onStats: onStats
                    ) { event in
                        continuation.yield(event)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        #else
        return AsyncThrowingStream { $0.finish(throwing: CoachRuntimeError.runtimeUnavailable) }
        #endif
    }

    /// Streams a plain-text completion of one system + user exchange, no tools.
    ///
    /// Backs the app's one-shot `suggestAdaptations` path.
    /// - Parameters:
    ///   - system: The system turn.
    ///   - user: The user turn.
    ///   - config: Sampling parameters.
    /// - Returns: Decoded text deltas.
    public func streamText(
        system: String,
        user: String,
        config: GenerationConfig = .production
    ) -> AsyncThrowingStream<String, Error> {
        #if canImport(MLXLLM)
        return AsyncThrowingStream { continuation in
            let task = Task {
                do {
                    try await self.generateText(system: system, user: user, config: config) {
                        continuation.yield($0)
                    }
                    continuation.finish()
                } catch {
                    continuation.finish(throwing: error)
                }
            }
            continuation.onTermination = { _ in task.cancel() }
        }
        #else
        return AsyncThrowingStream { $0.finish(throwing: CoachRuntimeError.runtimeUnavailable) }
        #endif
    }

    // MARK: - MLX-backed generation

    #if canImport(MLXLLM)

    /// Returns the cached container, loading it on demand.
    private func container() async throws -> ModelContainer {
        if let cachedContainer { return cachedContainer }
        try await load()
        return cachedContainer!
    }

    /// Maps the shared `GenerationConfig` onto the runtime's parameter type.
    private static func parameters(_ config: GenerationConfig) -> GenerateParameters {
        GenerateParameters(
            maxTokens: config.maxTokens,
            temperature: config.temperature,
            topP: config.topP,
            repetitionPenalty: config.repetitionPenalty,
            repetitionContextSize: config.repetitionContextSize
        )
    }

    /// Conversational generation with tools enabled.
    ///
    /// Uses the `AsyncStream<Generation>` overload of `MLXLMCommon.generate`,
    /// so detokenization goes through MLX's `NaiveStreamingDetokenizer` and
    /// tool calls arrive already parsed out of the text.
    private func generateChat(
        request: CoachChatRequest,
        today: Date,
        config: GenerationConfig,
        onStats: (@Sendable (GenerationStats) -> Void)?,
        onEvent: @escaping @Sendable (CoachEvent) -> Void
    ) async throws {
        let container = try await container()
        let parameters = Self.parameters(config)
        let turns = AICoachPromptBuilder.buildChatTurns(for: request, today: today)
        let tools = CoachToolSchemas.all(today: today)
        // Capture only `Sendable` values in the perform closure: `UserInput` is
        // non-Sendable, so it is built inside rather than captured from outside.
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
                    onEvent(CoachEventMapping.event(
                        toolName: call.function.name,
                        arguments: call.function.arguments.mapValues(\.anyValue)
                    ))
                case .rejectedToolCall(let rejection):
                    onEvent(.rejectedToolCall(reason: rejection.reason.rawValue))
                case .info(let info):
                    onStats?(Self.stats(from: info))
                @unknown default:
                    // The enum is not frozen — ignore anything that isn't content.
                    break
                }
            }
        }
    }

    /// One-shot generation: system + user turns, no tools.
    private func generateText(
        system: String,
        user: String,
        config: GenerationConfig,
        onChunk: @escaping @Sendable (String) -> Void
    ) async throws {
        let container = try await container()
        let parameters = Self.parameters(config)
        try await container.perform { context in
            let userInput = UserInput(chat: [.system(system), .user(user)])
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

    /// Maps a conversation turn to the runtime's chat message type.
    private static func chatMessage(from message: CoachMessage) -> Chat.Message {
        switch message.role {
        case .system: .system(message.text)
        case .user: .user(message.text)
        case .coach: .assistant(message.text)
        }
    }

    /// Copies the runtime's completion info into the MLX-free stats type.
    private static func stats(from info: GenerateCompletionInfo) -> GenerationStats {
        GenerationStats(
            promptTokens: info.promptTokenCount,
            generatedTokens: info.generationTokenCount,
            promptSeconds: info.promptTime,
            generateSeconds: info.generateTime
        )
    }

    #endif
}
