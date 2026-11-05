//
//  EvalRunner.swift
//  CoachEvalKit
//
//  Runs scenarios through a generator, grades every sample, and assembles a
//  RunRecord.
//

import Foundation
import AICoachCore

/// Progress events, so the CLI can print as it goes rather than after
/// minutes of silence.
public enum EvalProgress: Sendable {
    /// A sample is about to generate.
    case sampleStarted(scenario: EvalScenario, sample: Int, of: Int)
    /// A sample finished and was graded.
    case sampleFinished(scenario: EvalScenario, sample: Int, result: SampleResult)
}

/// Runs and grades scenarios.
///
/// Samples run one after another, never concurrently: there is one model on
/// one GPU, and `ModelContainer.perform` would serialize them anyway.
public struct EvalRunner: Sendable {

    /// Produces the coach's turns.
    public let generator: any CoachTurnGenerator
    /// Sampling parameters for every turn.
    public var config: GenerationConfig
    /// Turns generated per scenario. Sampling is random (temperature > 0), so
    /// one sample says little; a pass rate over several says more.
    public var samples: Int

    /// Creates a runner.
    public init(generator: any CoachTurnGenerator, config: GenerationConfig = .chat, samples: Int = 1) {
        self.generator = generator
        self.config = config
        self.samples = max(samples, 1)
    }

    /// Runs every scenario `samples` times.
    /// - Parameters:
    ///   - scenarios: What to run, in order.
    ///   - gitCommit: Recorded on the result for later comparison.
    ///   - note: Free-form note recorded on the result.
    ///   - progress: Called before and after each sample.
    /// - Returns: The graded run.
    public func run(
        _ scenarios: [EvalScenario],
        gitCommit: String? = nil,
        note: String? = nil,
        progress: (@Sendable (EvalProgress) -> Void)? = nil
    ) async -> RunRecord {
        let startedAt = Date()
        var results: [ScenarioResult] = []
        for scenario in scenarios {
            var sampleResults: [SampleResult] = []
            for index in 0..<samples {
                if Task.isCancelled { break }
                progress?(.sampleStarted(scenario: scenario, sample: index + 1, of: samples))
                let result = await runSample(scenario)
                sampleResults.append(result)
                progress?(.sampleFinished(scenario: scenario, sample: index + 1, result: result))
            }
            results.append(ScenarioResult(
                id: scenario.id,
                title: scenario.title,
                tags: scenario.tags.sorted(),
                samples: sampleResults
            ))
        }
        return RunRecord(
            startedAt: startedAt,
            gitCommit: gitCommit,
            note: note,
            modelID: generator.modelID,
            config: config,
            samplesPerScenario: samples,
            scenarios: results
        )
    }

    /// Generates and grades one sample. A generation error becomes a failed
    /// sample rather than aborting the run.
    func runSample(_ scenario: EvalScenario) async -> SampleResult {
        do {
            let transcript = try await generator.respond(
                to: scenario.chatRequest(), today: scenario.today, config: config
            )
            return Self.grade(transcript, for: scenario)
        } catch {
            return SampleResult(
                checks: scenario.expectations.map {
                    CheckResult(label: $0.label, passed: false, detail: "generation failed")
                },
                reply: "",
                proposal: nil,
                rejections: [],
                error: error.localizedDescription
            )
        }
    }

    /// Applies a scenario's expectations to a transcript.
    /// - Parameters:
    ///   - transcript: The coach's turn.
    ///   - scenario: Supplies the expectations and "today".
    /// - Returns: The graded sample.
    public static func grade(_ transcript: TurnTranscript, for scenario: EvalScenario) -> SampleResult {
        let checks = scenario.expectations.map { expectation in
            let verdict = expectation.evaluate(transcript, scenario)
            return CheckResult(label: expectation.label, passed: verdict.passed, detail: verdict.detail)
        }
        return SampleResult(
            checks: checks,
            reply: transcript.trimmedReply,
            proposal: transcript.proposal.map(ProposalSummary.describe),
            rejections: transcript.rejections,
            stats: transcript.stats
        )
    }
}
