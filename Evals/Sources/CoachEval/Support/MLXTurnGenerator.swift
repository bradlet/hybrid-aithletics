//
//  MLXTurnGenerator.swift
//  CoachEval
//
//  The real thing: generates coach turns with AICoachRuntime's CoachRuntime —
//  the same type the iOS app's MLXAICoachService forwards to — on the Mac's
//  GPU via Metal.
//

import Foundation
import AICoachCore
import AICoachRuntime
import CoachEvalKit

/// A `CoachTurnGenerator` backed by the production model runtime.
struct MLXTurnGenerator: CoachTurnGenerator {

    /// The loaded runtime. Create one per process; loading takes seconds and
    /// gigabytes.
    let runtime: CoachRuntime

    var modelID: String { runtime.preset.id }

    func respond(
        to request: CoachChatRequest,
        today: Date,
        config: GenerationConfig
    ) async throws -> TurnTranscript {
        let stats = StatsBox()
        var transcript = try await TurnTranscript.collecting(
            runtime.streamChat(request, today: today, config: config) { stats.value = $0 }
        )
        transcript.stats = stats.value.map(TurnStats.init)
        return transcript
    }
}

extension TurnStats {
    /// Copies the runtime's stats into the eval kit's MLX-free type.
    init(_ stats: GenerationStats) {
        self.init(
            promptTokens: stats.promptTokens,
            generatedTokens: stats.generatedTokens,
            promptSeconds: stats.promptSeconds,
            generateSeconds: stats.generateSeconds
        )
    }
}

/// Holds the stats a `@Sendable` callback reports, for reading afterwards.
///
/// The callback may run on another thread, so access goes through a lock.
final class StatsBox: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: GenerationStats?

    /// The last stats reported, if any.
    var value: GenerationStats? {
        get { lock.withLock { stored } }
        set { lock.withLock { stored = newValue } }
    }
}

/// Loads the production model, printing download progress and load time.
enum ModelLoader {

    /// Creates and loads a runtime for `CoachModelPreset.production`.
    ///
    /// The first run downloads ~4.3 GB into `~/Documents/huggingface`, the same
    /// Hub cache layout the app uses on device; later runs load from disk.
    static func loadProduction() async throws -> CoachRuntime {
        let runtime = CoachRuntime(preset: .production)
        let cached = runtime.isCached
        Terminal.status("Loading \(runtime.preset.id)\(cached ? "" : " (downloading first — ~4.3 GB)")…")
        let started = Date()
        let lastPercent = PercentGate()
        try await runtime.load { progress in
            guard !cached else { return }
            let percent = Int(progress.fractionCompleted * 100)
            if lastPercent.advance(to: percent) {
                Terminal.status("  download \(percent)%")
            }
        }
        Terminal.status(String(format: "Model ready in %.1fs.\n", Date().timeIntervalSince(started)))
        return runtime
    }
}

/// Remembers the last printed download percentage so each is printed once.
private final class PercentGate: @unchecked Sendable {
    private let lock = NSLock()
    private var last = -1

    /// Whether `percent` is new and worth printing (every 5%).
    func advance(to percent: Int) -> Bool {
        lock.withLock {
            guard percent != last, percent % 5 == 0 else { return false }
            last = percent
            return true
        }
    }
}
