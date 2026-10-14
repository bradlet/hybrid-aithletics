//
//  MLXModelLoading.swift
//  Hybrid AIthletics
//
//  Hugging Face model delivery for the on-device coach.
//
//  mlx-swift-lm 3.0 removed its bundled Hugging Face Hub integration and its
//  dependency on swift-transformers: `MLXLMCommon` now declares provider-agnostic
//  `Downloader` and `TokenizerLoader` protocols and expects the caller to supply
//  conformances. This file is that supply — it wires swift-transformers' `HubApi`
//  and `AutoTokenizer` into the shapes `LLMModelFactory.loadContainer` wants.
//
//  Everything here is gated behind `#if canImport(MLXLLM)` so the app still
//  compiles where the MLX packages have not been resolved.
//

import Foundation

#if canImport(MLXLLM)
import Hub
import MLXLMCommon
import Tokenizers

// MARK: - Download

/// Downloads model repository snapshots from Hugging Face.
///
/// Replaces the Hub integration that mlx-swift-lm shipped before 3.0. `HubApi`
/// handles the cache check internally, so a repository already on disk resolves
/// without network access — which is what keeps the coach working offline after
/// the first download.
struct HuggingFaceDownloader: Downloader {

    /// The Hub client used for snapshot downloads. `HubApi.shared` caches under
    /// the default `downloadBase`, which `isModelCached` also reads.
    let hub: HubApi

    init(hub: HubApi = .shared) {
        self.hub = hub
    }

    /// Downloads (or retrieves from cache) the files matching `patterns`.
    /// - Parameters:
    ///   - id: Hugging Face repository identifier, e.g. `"mlx-community/gemma-3-4b-it-qat-4bit"`.
    ///   - revision: Branch, tag, or commit. `nil` means the repository default.
    ///   - patterns: Glob patterns selecting which files to fetch.
    ///   - useLatest: Ignored — `HubApi` always prefers its cache when present,
    ///     which is the behavior the coach wants on a metered connection.
    ///   - progressHandler: Called with download progress.
    /// - Returns: The local directory holding the snapshot.
    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let repo = Hub.Repo(id: id)
        if let revision {
            return try await hub.snapshot(
                from: repo,
                revision: revision,
                matching: patterns,
                progressHandler: progressHandler
            )
        }
        return try await hub.snapshot(
            from: repo,
            matching: patterns,
            progressHandler: progressHandler
        )
    }
}

// MARK: - Tokenizer

/// Loads a tokenizer from a downloaded snapshot directory.
struct HuggingFaceTokenizerLoader: TokenizerLoader {

    /// The Hub client passed through to `AutoTokenizer`. Unused for local
    /// loading, but the API requires one.
    let hub: HubApi

    init(hub: HubApi = .shared) {
        self.hub = hub
    }

    /// Reads `tokenizer.json` / `tokenizer_config.json` out of `directory`.
    /// - Parameter directory: A snapshot directory produced by `HuggingFaceDownloader`.
    /// - Returns: The tokenizer, adapted to `MLXLMCommon.Tokenizer`.
    func load(from directory: URL) async throws -> any MLXLMCommon.Tokenizer {
        let tokenizer = try await AutoTokenizer.from(modelFolder: directory, hubApi: hub)
        return MLXTokenizerAdapter(wrapped: tokenizer)
    }
}

/// Bridges swift-transformers' `Tokenizer` to `MLXLMCommon.Tokenizer`.
///
/// The two protocols are structurally near-identical — mlx-swift-lm 3.0 declared
/// its own copy precisely so it could drop the swift-transformers dependency — so
/// this is a pure forwarding shim. The only real difference is the decode
/// argument label (`tokens:` vs `tokenIds:`).
struct MLXTokenizerAdapter: MLXLMCommon.Tokenizer {

    /// The underlying swift-transformers tokenizer.
    let wrapped: any Tokenizers.Tokenizer

    func encode(text: String, addSpecialTokens: Bool) -> [Int] {
        wrapped.encode(text: text, addSpecialTokens: addSpecialTokens)
    }

    func decode(tokenIds: [Int], skipSpecialTokens: Bool) -> String {
        wrapped.decode(tokens: tokenIds, skipSpecialTokens: skipSpecialTokens)
    }

    func convertTokenToId(_ token: String) -> Int? {
        wrapped.convertTokenToId(token)
    }

    func convertIdToToken(_ id: Int) -> String? {
        wrapped.convertIdToToken(id)
    }

    var bosToken: String? { wrapped.bosToken }
    var eosToken: String? { wrapped.eosToken }
    var unknownToken: String? { wrapped.unknownToken }

    func applyChatTemplate(
        messages: [[String: any Sendable]],
        tools: [[String: any Sendable]]?,
        additionalContext: [String: any Sendable]?
    ) throws -> [Int] {
        try wrapped.applyChatTemplate(
            messages: messages,
            tools: tools,
            additionalContext: additionalContext
        )
    }
}

// MARK: - Cache inspection

/// Whether a Hugging Face repository is already materialized on disk.
///
/// mlx-swift-lm 3.x moved `ModelConfiguration.modelDirectory()` behind `package`
/// protection, so the cached-weights check reads `HubApi`'s snapshot location
/// directly. `config.json` is the marker file: it is small, always present in an
/// MLX repository, and written as part of the snapshot.
/// - Parameters:
///   - modelID: Hugging Face repository identifier.
///   - hub: The Hub client whose `downloadBase` to inspect.
/// - Returns: `true` when the snapshot looks complete enough to load offline.
func isHuggingFaceRepoCached(_ modelID: String, hub: HubApi = .shared) -> Bool {
    let directory = hub.localRepoLocation(Hub.Repo(id: modelID))
    return FileManager.default.fileExists(
        atPath: directory.appendingPathComponent("config.json").path
    )
}

#endif
