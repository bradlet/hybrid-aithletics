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

/// Downloads model repository snapshots from Hugging Face, reporting
/// byte-weighted progress.
///
/// Replaces the Hub integration that mlx-swift-lm shipped before 3.0. `HubApi`
/// handles the cache check internally, so a repository already on disk resolves
/// without network access — which is what keeps the coach working offline after
/// the first download.
///
/// ## Why progress is measured from disk
///
/// `HubApi.snapshot` reports a `Progress` whose children are weighted one unit
/// per *file*, regardless of size. The coach model is a single 4.3 GB weights
/// file beside nine files totalling ~33 MB, so that fraction reaches 90% within
/// seconds and then sits there for the whole real download — a bar that moves
/// but tells the user nothing.
///
/// So this type ignores that fraction. It asks the Hub API for the size of every
/// file it is about to fetch, then polls the repository directory (partial
/// downloads land as `.incomplete` files inside it) and reports actual bytes on
/// disk against that total. That is accurate, survives a resumed download — the
/// bytes already present count immediately — and generalizes to sharded repos.
/// If the size lookup fails, it falls back to forwarding `HubApi`'s own
/// progress rather than showing nothing.
struct HuggingFaceDownloader: Downloader {

    /// How often the on-disk byte count is sampled during a download.
    private static let pollInterval: Duration = .milliseconds(400)

    /// The Hub client used for snapshot downloads. `HubApi.shared` caches under
    /// the default `downloadBase`, which the cache check also reads.
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
        let expectedBytes = await Self.expectedBytes(
            repoID: id, revision: revision, matching: patterns
        )

        // Without a known total there is nothing to weight against, so fall
        // back to the Hub's own (file-count-weighted) progress.
        guard expectedBytes > 0 else {
            return try await snapshot(
                repo: repo,
                revision: revision,
                patterns: patterns,
                progressHandler: progressHandler
            )
        }

        let directory = hub.localRepoLocation(repo)
        let poller = Task {
            while !Task.isCancelled {
                // `discreteProgress` rather than `init(totalUnitCount:)`: the
                // latter implicitly attaches to any ambient current progress,
                // which would reparent these samples into someone else's tree.
                let progress = Progress.discreteProgress(totalUnitCount: expectedBytes)
                progress.completedUnitCount = min(
                    Self.directorySize(at: directory), expectedBytes
                )
                progressHandler(progress)
                try? await Task.sleep(for: Self.pollInterval)
            }
        }
        defer { poller.cancel() }

        // The Hub's own handler is dropped: reporting both would make the
        // fraction jump between two different weightings.
        let result = try await snapshot(
            repo: repo, revision: revision, patterns: patterns, progressHandler: { _ in }
        )

        poller.cancel()
        // Land on exactly 100% — the last poll almost certainly fired mid-write.
        let finished = Progress.discreteProgress(totalUnitCount: expectedBytes)
        finished.completedUnitCount = expectedBytes
        progressHandler(finished)
        return result
    }

    /// Calls `HubApi.snapshot`, forwarding `revision` only when one was given.
    private func snapshot(
        repo: Hub.Repo,
        revision: String?,
        patterns: [String],
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        if let revision {
            return try await hub.snapshot(
                from: repo, revision: revision, matching: patterns,
                progressHandler: progressHandler
            )
        }
        return try await hub.snapshot(
            from: repo, matching: patterns, progressHandler: progressHandler
        )
    }

    // MARK: - Size discovery

    /// Total size of the repository files matching `patterns`, or `0` when the
    /// lookup fails (offline, rate limited, private repo).
    static func expectedBytes(
        repoID: String,
        revision: String?,
        matching patterns: [String]
    ) async -> Int64 {
        var components = URLComponents(
            string: "https://huggingface.co/api/models/\(repoID)"
        )
        if let revision {
            components = URLComponents(
                string: "https://huggingface.co/api/models/\(repoID)/revision/\(revision)"
            )
        }
        components?.queryItems = [URLQueryItem(name: "blobs", value: "true")]
        guard let url = components?.url else { return 0 }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return 0 }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let siblings = json["siblings"] as? [[String: Any]]
            else { return 0 }

            return siblings.reduce(into: Int64(0)) { total, sibling in
                guard
                    let name = sibling["rfilename"] as? String,
                    matches(name, patterns: patterns),
                    let size = sibling["size"] as? NSNumber
                else { return }
                total += size.int64Value
            }
        } catch {
            return 0
        }
    }

    /// Whether `filename` matches any of the Hub glob patterns.
    ///
    /// Only the `*.ext` and `*` forms MLX actually uses are handled; anything
    /// more exotic is treated as a literal name.
    static func matches(_ filename: String, patterns: [String]) -> Bool {
        for pattern in patterns {
            if pattern == "*" { return true }
            if pattern.hasPrefix("*.") {
                if filename.hasSuffix(String(pattern.dropFirst())) { return true }
            } else if pattern == filename {
                return true
            }
        }
        return false
    }

    /// Total bytes of every regular file under `directory`, including the
    /// `.incomplete` partials the Hub writes while downloading.
    static func directorySize(at directory: URL) -> Int64 {
        guard let enumerator = FileManager.default.enumerator(
            at: directory,
            includingPropertiesForKeys: [.isRegularFileKey, .fileAllocatedSizeKey, .fileSizeKey],
            options: []
        ) else { return 0 }

        var total: Int64 = 0
        for case let url as URL in enumerator {
            let values = try? url.resourceValues(
                forKeys: [.isRegularFileKey, .fileSizeKey]
            )
            guard values?.isRegularFile == true, let size = values?.fileSize else { continue }
            total += Int64(size)
        }
        return total
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

/// Whether a Hugging Face repository is fully materialized on disk.
///
/// mlx-swift-lm 3.x moved `ModelConfiguration.modelDirectory()` behind `package`
/// protection, so this reads `HubApi`'s snapshot location directly.
///
/// `config.json` alone is not a sufficient marker: it is a few hundred bytes and
/// lands within the first second of a 4.3 GB download, so an interrupted
/// download would report itself as cached and then fail to load. This requires
/// weights to be present *and* no `.incomplete` partial to be left behind.
/// - Parameters:
///   - modelID: Hugging Face repository identifier.
///   - hub: The Hub client whose `downloadBase` to inspect.
/// - Returns: `true` when the snapshot looks complete enough to load offline.
func isHuggingFaceRepoCached(_ modelID: String, hub: HubApi = .shared) -> Bool {
    let directory = hub.localRepoLocation(Hub.Repo(id: modelID))
    let fileManager = FileManager.default

    guard fileManager.fileExists(
        atPath: directory.appendingPathComponent("config.json").path
    ) else { return false }

    guard let entries = try? fileManager.contentsOfDirectory(atPath: directory.path),
          entries.contains(where: { $0.hasSuffix(".safetensors") })
    else { return false }

    // Partial downloads live under <repo>/.cache/huggingface/download as
    // "<name>.<etag>.incomplete". Any survivor means the snapshot is unfinished.
    let downloadCache = directory
        .appendingPathComponent(".cache")
        .appendingPathComponent("huggingface")
        .appendingPathComponent("download")
    if let enumerator = fileManager.enumerator(atPath: downloadCache.path) {
        for case let path as String in enumerator where path.hasSuffix(".incomplete") {
            return false
        }
    }
    return true
}

#endif
