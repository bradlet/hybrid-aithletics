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
/// ## Why progress is assembled per file
///
/// `HubApi.snapshot` reports a `Progress` whose children are weighted one unit
/// per *file*, regardless of size. The coach model is a single 4.3 GB weights
/// file beside nine files totalling ~33 MB, so that fraction reaches 90% within
/// seconds and then crawls through the remaining 10% for the whole real
/// download — a bar that lies about where it is.
///
/// Watching the filesystem instead does not work either, and this is worth
/// recording because it looks like it should: the underlying transfer runs
/// through `URLSession.download`, which streams into a file in the *system
/// temporary directory* and only `moveItem`s it into the repository directory
/// once the file is complete. A repo directory poll therefore shows the small
/// files, nothing at all for minutes, then the full 4.3 GB at once.
///
/// What is accurate is the per-file fraction `HubApi` already computes from
/// `URLSession`'s byte counts. So this type asks the Hub API for the size of
/// every file it is about to fetch, then downloads them **one at a time** —
/// each `snapshot` call matching a single filename, whose progress is that one
/// file's true byte fraction — and weights each file's fraction by its real
/// size. Files already cached resolve instantly and count immediately, so a
/// resumed download starts part-way along. If the size lookup fails, it falls
/// back to forwarding `HubApi`'s own progress rather than showing nothing.
///
/// Don't "simplify" this back into a single `snapshot` call over all patterns.
struct HuggingFaceDownloader: Downloader {

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
    ///   - progressHandler: Called with byte-weighted download progress. The
    ///     reported `Progress` carries a smoothed bytes-per-second rate under
    ///     `ProgressUserInfoKey.throughputKey`.
    /// - Returns: The local directory holding the snapshot.
    func download(
        id: String,
        revision: String?,
        matching patterns: [String],
        useLatest: Bool,
        progressHandler: @Sendable @escaping (Progress) -> Void
    ) async throws -> URL {
        let repo = Hub.Repo(id: id)
        let sizes = await Self.remoteFileSizes(
            repoID: id, revision: revision, matching: patterns
        )

        // Without known sizes there is nothing to weight against, so fall back
        // to the Hub's own (file-count-weighted) progress.
        guard !sizes.isEmpty else {
            return try await snapshot(
                repo: repo,
                revision: revision,
                patterns: patterns,
                progressHandler: progressHandler
            )
        }

        let totalBytes = sizes.values.reduce(0, +)
        let meter = ByteRateMeter()
        let report: @Sendable (Int64) -> Void = { bytes in
            let progress = Progress.discreteProgress(totalUnitCount: totalBytes)
            progress.completedUnitCount = min(max(bytes, 0), totalBytes)
            if let rate = meter.sample(bytes: progress.completedUnitCount) {
                progress.setUserInfoObject(rate, forKey: .throughputKey)
            }
            progressHandler(progress)
        }

        // Smallest first: the config and tokenizer files land in the first
        // second, so the bar proves itself alive before the long haul, and a
        // failure on the weights still leaves the cheap files cached.
        let ordered = sizes.sorted { ($0.value, $0.key) < ($1.value, $1.key) }
        var finishedBytes: Int64 = 0
        report(0)

        for (filename, size) in ordered {
            let base = finishedBytes
            _ = try await snapshot(
                repo: repo,
                revision: revision,
                // A filename with no glob metacharacters matches only itself
                // under the Hub's `fnmatch`, so this fetches exactly one file
                // and its progress is that file's own byte fraction.
                patterns: [filename],
                progressHandler: { fileProgress in
                    let within = Int64(
                        (fileProgress.fractionCompleted * Double(size)).rounded()
                    )
                    report(base + within)
                }
            )
            finishedBytes += size
            report(finishedBytes)
        }

        return hub.localRepoLocation(repo)
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

    /// Size in bytes of every repository file matching `patterns`, keyed by
    /// filename. Empty when the lookup fails (offline, rate limited, private
    /// repo) or when no file both matches and reports a size.
    static func remoteFileSizes(
        repoID: String,
        revision: String?,
        matching patterns: [String]
    ) async -> [String: Int64] {
        var components = URLComponents(
            string: "https://huggingface.co/api/models/\(repoID)"
        )
        if let revision {
            components = URLComponents(
                string: "https://huggingface.co/api/models/\(repoID)/revision/\(revision)"
            )
        }
        components?.queryItems = [URLQueryItem(name: "blobs", value: "true")]
        guard let url = components?.url else { return [:] }

        do {
            let (data, response) = try await URLSession.shared.data(from: url)
            guard (response as? HTTPURLResponse)?.statusCode == 200 else { return [:] }
            guard
                let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
                let siblings = json["siblings"] as? [[String: Any]]
            else { return [:] }

            return siblings.reduce(into: [String: Int64]()) { sizes, sibling in
                guard
                    let name = sibling["rfilename"] as? String,
                    matches(name, patterns: patterns),
                    let size = sibling["size"] as? NSNumber,
                    size.int64Value > 0
                else { return }
                sizes[name] = size.int64Value
            }
        } catch {
            return [:]
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
}

/// Smoothed download rate, in bytes per second.
///
/// Exists so the progress card can say *why* a download is taking four minutes
/// instead of leaving the athlete to guess whether it has hung. Samples are
/// exponentially smoothed because `URLSession` delivers byte counts in bursts,
/// and a raw delta reads as wild oscillation.
///
/// A class with a lock rather than an actor: it is driven from whichever thread
/// `URLSession` calls back on, inside a synchronous `@Sendable` closure that
/// cannot await.
final class ByteRateMeter: @unchecked Sendable {

    /// Weight given to the newest sample. Low enough that one stalled interval
    /// doesn't read as a stop.
    private static let smoothing = 0.3

    /// Minimum gap between samples. Below this the deltas are too small to
    /// divide meaningfully.
    private static let minimumInterval: TimeInterval = 0.3

    /// Ceiling applied to a single sample, to absorb the step change when one
    /// file finishes and the next begins.
    private static let maximumRate: Double = 500 * 1024 * 1024

    private let lock = NSLock()
    private var lastBytes: Int64?
    private var lastSampledAt: Date?
    private var smoothed: Double?

    /// Folds a cumulative byte count into the rate estimate.
    /// - Parameter bytes: Total bytes transferred so far.
    /// - Returns: The smoothed rate in bytes per second, or `nil` before enough
    ///   time has passed to compute one.
    func sample(bytes: Int64) -> Double? {
        lock.lock()
        defer { lock.unlock() }

        let now = Date()
        guard let previousBytes = lastBytes, let previousAt = lastSampledAt else {
            lastBytes = bytes
            lastSampledAt = now
            return nil
        }

        let elapsed = now.timeIntervalSince(previousAt)
        guard elapsed >= Self.minimumInterval else { return smoothed }

        lastBytes = bytes
        lastSampledAt = now

        let instant = min(
            max(Double(bytes - previousBytes) / elapsed, 0), Self.maximumRate
        )
        smoothed = smoothed.map {
            $0 * (1 - Self.smoothing) + instant * Self.smoothing
        } ?? instant
        return smoothed
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
/// weights to be present — and a `.safetensors` file only appears here once it
/// has transferred completely, since the Hub downloads into a temporary file
/// and moves it into place at the end — *and* no `.incomplete` partial left
/// behind by an older download.
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
