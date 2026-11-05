//
//  AICoachRuntimeTests.swift
//  AICoachRuntimeTests
//
//  Model-free tests for the coach runtime: presets, tool-call → event mapping,
//  download progress helpers. Nothing here loads weights or touches Metal.
//

import Foundation
import Testing
import AICoachCore
@testable import AICoachRuntime
#if canImport(MLXLMCommon)
import MLXLMCommon
#endif

// MARK: - Model Preset Tests

struct CoachModelPresetTests {

    @Test func productionPresetIsGemma4E2B() {
        let preset = CoachModelPreset.production
        #expect(preset.id == "lmstudio-community/gemma-4-E2B-it-MLX-4bit")
        #expect(preset.approximateDownloadBytes > 4_000_000_000)
    }

    @Test func productionPresetPairsTheGemma4DialectWithItsEndOfTurnToken() {
        // A mismatched pair fails silently: tool calls stream out as text, or
        // generation runs to maxTokens. They must change together.
        let preset = CoachModelPreset.production
        #expect(preset.toolCallFormat == "gemma4")
        #expect(preset.extraEOSTokens == ["<turn|>"])
    }

    #if canImport(MLXLMCommon)
    @Test func productionToolCallFormatIsKnownToTheRuntime() {
        #expect(ToolCallFormat(rawValue: CoachModelPreset.production.toolCallFormat) != nil)
    }
    #endif
}

// MARK: - Runtime Construction Tests

struct CoachRuntimeTests {

    @Test func newRuntimeIsNotReady() {
        let runtime = CoachRuntime(preset: .production)
        #expect(!runtime.isReady)
        #expect(runtime.preset == .production)
        #expect(runtime.memoryCacheLimit == nil)
    }

    @Test func keepsTheMemoryCacheLimitItWasGiven() {
        let runtime = CoachRuntime(memoryCacheLimit: 20 * 1024 * 1024)
        #expect(runtime.memoryCacheLimit == 20 * 1024 * 1024)
    }

    @Test func unknownToolCallFormatFailsLoadingBeforeAnyDownload() async {
        let preset = CoachModelPreset(
            id: "example/not-a-model", extraEOSTokens: [],
            toolCallFormat: "no-such-format", approximateDownloadBytes: 0
        )
        await #expect(throws: CoachRuntimeError.self) {
            try await CoachRuntime(preset: preset).load()
        }
    }
}

// MARK: - Event Mapping Tests

struct CoachEventMappingTests {

    @Test func validChatCallBecomesAnAction() {
        let event = CoachEventMapping.event(toolName: "chat", arguments: ["message": "Rest up."])
        #expect(event == .action(.reply("Rest up.")))
    }

    @Test func unknownToolIsRejectedNotThrown() {
        let event = CoachEventMapping.event(toolName: "launch_rocket", arguments: [:])
        guard case .rejectedToolCall(let reason) = event else {
            Issue.record("Expected a rejection, got \(event)")
            return
        }
        #expect(!reason.isEmpty)
    }

    @Test func workoutWithNoSizeIsRejected() {
        // The decoder refuses a workout with neither distance nor duration;
        // the mapping must surface that as a rejection, not an action.
        let event = CoachEventMapping.event(
            toolName: "record_workout",
            arguments: ["date": "2026-11-03", "type": "Easy Run"]
        )
        guard case .rejectedToolCall = event else {
            Issue.record("Expected a rejection, got \(event)")
            return
        }
    }
}

// MARK: - Generation Stats Tests

struct GenerationStatsTests {

    @Test func tokensPerSecondDividesGeneratedTokensByGenerateTime() {
        let stats = GenerationStats(
            promptTokens: 900, generatedTokens: 120, promptSeconds: 1, generateSeconds: 4
        )
        #expect(stats.tokensPerSecond == 30)
    }

    @Test func tokensPerSecondIsZeroBeforeAnyTimeElapsed() {
        let stats = GenerationStats(
            promptTokens: 0, generatedTokens: 0, promptSeconds: 0, generateSeconds: 0
        )
        #expect(stats.tokensPerSecond == 0)
    }
}

// MARK: - Hugging Face Download Pattern Tests

struct HuggingFaceDownloadPatternTests {

    @Test func matchesExtensionGlobs() {
        let patterns = ["*.safetensors", "*.json", "*.jinja"]
        #expect(HuggingFaceDownloader.matches("model.safetensors", patterns: patterns))
        #expect(HuggingFaceDownloader.matches("config.json", patterns: patterns))
        #expect(HuggingFaceDownloader.matches("chat_template.jinja", patterns: patterns))
    }

    @Test func rejectsFilesTheDownloadWouldSkip() {
        // README.md and .gitattributes are not fetched, so counting their bytes
        // toward the total would make the bar stop short of 100%.
        let patterns = ["*.safetensors", "*.json", "*.jinja"]
        #expect(!HuggingFaceDownloader.matches("README.md", patterns: patterns))
        #expect(!HuggingFaceDownloader.matches(".gitattributes", patterns: patterns))
    }

    @Test func matchesLiteralNamesAndWildcard() {
        #expect(HuggingFaceDownloader.matches("config.json", patterns: ["config.json"]))
        #expect(HuggingFaceDownloader.matches("anything.bin", patterns: ["*"]))
        #expect(!HuggingFaceDownloader.matches("other.json", patterns: ["config.json"]))
    }

}

// MARK: - Byte Rate Meter Tests

struct ByteRateMeterTests {

    @Test func firstSampleHasNoRateYet() {
        // One cumulative reading is not a rate; reporting 0 would read as a
        // stalled download on the very first progress callback.
        #expect(ByteRateMeter().sample(bytes: 1_000) == nil)
    }

    @Test func samplesTakenTooCloseTogetherHoldTheLastRate() {
        let meter = ByteRateMeter()
        _ = meter.sample(bytes: 0)
        // URLSession delivers byte counts in bursts; dividing by a 1 ms gap
        // would produce nonsense, so sub-interval samples are held.
        #expect(meter.sample(bytes: 5_000) == nil)
    }

    @Test func measuresARateOnceEnoughTimeHasPassed() async throws {
        let meter = ByteRateMeter()
        _ = meter.sample(bytes: 0)
        try await Task.sleep(for: .milliseconds(400))
        let rate = try #require(meter.sample(bytes: 1_000_000))
        // ~1 MB over ~0.4 s. Generous bounds: this is wall-clock timing.
        #expect(rate > 500_000)
        #expect(rate < 10_000_000)
    }

    @Test func rateIsNeverNegativeWhenTheByteCountDoesNotAdvance() async throws {
        let meter = ByteRateMeter()
        _ = meter.sample(bytes: 5_000)
        try await Task.sleep(for: .milliseconds(400))
        let rate = try #require(meter.sample(bytes: 5_000))
        #expect(rate == 0)
    }
}
