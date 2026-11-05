//
//  RunEvalsCommand.swift
//  CoachEval
//
//  Runs evaluation scenarios against the model and reports quality scores.
//

import ArgumentParser
import Foundation
import AICoachCore

struct RunEvalsCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run evaluation scenarios and report quality scores."
    )

    @Option(name: .long, help: "Run only this scenario ID (e.g. high-rpe).")
    var scenario: String?

    @Option(name: .long, help: "Prompt mode: flat (one user message) or chat (system/user roles).")
    var promptMode: String = "chat"

    @Option(name: .long, help: "Override temperature (e.g. 0.3).")
    var temperature: Float?

    @Option(name: .long, help: "Override top-p (e.g. 0.85).")
    var topP: Float?

    @Option(name: .long, help: "Override repetition penalty (e.g. 1.2).")
    var repetitionPenalty: Float?

    @Option(name: .long, help: "Override max tokens (e.g. 300).")
    var maxTokens: Int?

    @Option(name: .long, help: "Number of iterations per scenario (default: 1).")
    var iterations: Int = 1

    func run() async throws {
        guard let mode = PromptMode(rawValue: promptMode) else {
            print("Error: --prompt-mode must be 'flat' or 'chat'")
            throw ExitCode.validationFailure
        }

        let scenarios: [EvalScenario]
        if let id = scenario {
            guard let s = ScenarioLibrary.scenario(id: id) else {
                print("Error: Unknown scenario '\(id)'. Available: \(ScenarioLibrary.all.map(\.id).joined(separator: ", "))")
                throw ExitCode.validationFailure
            }
            scenarios = [s]
        } else {
            scenarios = ScenarioLibrary.all
        }

        var config = GenerationConfig.production
        if let t = temperature { config.temperature = t }
        if let p = topP { config.topP = p }
        if let r = repetitionPenalty { config.repetitionPenalty = r }
        if let m = maxTokens { config.maxTokens = m }

        let generator = CoachGenerator()
        try await generator.loadModel()

        var totalScore = 0
        var totalMax = 0
        var runCount = 0

        for s in scenarios {
            for i in 0..<iterations {
                if iterations > 1 {
                    print("\n--- Iteration \(i + 1)/\(iterations) ---")
                }

                let result = try await generator.generate(
                    request: s.request,
                    config: config,
                    promptMode: mode
                )

                let score = QualityScorer.score(output: result.output, scenario: s)
                totalScore += score.total
                totalMax += score.maxTotal
                runCount += 1

                EvalReport.printReport(
                    scenario: s,
                    output: result.output,
                    score: score,
                    promptMode: mode.rawValue,
                    tokensPerSecond: result.tokensPerSecond,
                    totalTime: result.totalTime
                )
            }
        }

        if runCount > 1 {
            print(String(repeating: "=", count: 60))
            print("Overall: \(totalScore)/\(totalMax) across \(runCount) runs " +
                  "(\(String(format: "%.0f", Double(totalScore) / Double(totalMax) * 100))%)")
            print("")
        }
    }
}
