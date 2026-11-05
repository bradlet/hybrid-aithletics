//
//  RunCommand.swift
//  CoachEval
//
//  Runs scenarios against the real model and grades them.
//

import ArgumentParser
import Foundation
import CoachEvalKit

struct RunCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "run",
        abstract: "Run scenarios against the production model on Metal and grade them."
    )

    @Option(name: .long, help: "Scenario id to run; repeat for several (default: all).")
    var scenario: [String] = []

    @Option(name: .long, help: "Run only scenarios with this tag (see `list`).")
    var tag: String?

    @Option(name: .long, help: "Turns generated per scenario. Sampling is random, so >1 gives a pass rate.")
    var samples: Int = 3

    @OptionGroup var generation: GenerationOptions

    @Flag(name: .long, help: "Save the run as JSON under Evals/results/ for `compare`.")
    var save = false

    @Option(name: .long, help: "Note stored with a saved run, e.g. what prompt change it tests.")
    var note: String?

    @Flag(name: .long, help: "Print every sample's reply, not just failures'.")
    var verbose = false

    @Flag(name: .long, help: "Exit non-zero unless every sample passes.")
    var strict = false

    func validate() throws {
        guard samples >= 1 else { throw ValidationError("--samples must be at least 1.") }
        for id in scenario { _ = try ScenarioLookup.require(id) }
        if let tag, !ScenarioLibrary.tags.contains(tag) {
            throw ValidationError("Unknown tag '\(tag)'. Available: \(ScenarioLibrary.tags.joined(separator: ", "))")
        }
    }

    func run() async throws {
        let scenarios = ScenarioLibrary.select(ids: scenario, tag: tag)
        guard !scenarios.isEmpty else {
            throw ValidationError("No scenarios match those filters.")
        }

        let runtime = try await ModelLoader.loadProduction()
        let runner = EvalRunner(
            generator: MLXTurnGenerator(runtime: runtime),
            config: generation.config,
            samples: samples
        )
        let verbose = self.verbose
        let record = await runner.run(scenarios, gitCommit: Git.describeHead(), note: note) { event in
            switch event {
            case .sampleStarted(let scenario, let sample, _) where sample == 1:
                Terminal.status("\n▶ \(scenario.id) — \(scenario.title)")
                Terminal.status("  \"\(scenario.athleteMessage)\"")
            case .sampleStarted:
                break
            case .sampleFinished(_, let sample, let result):
                Terminal.status(ReportFormatter.sampleLine(result, sample: sample, of: runner.samples))
                if !result.passed {
                    Terminal.status(ReportFormatter.failureDetail(result))
                } else if verbose, !result.reply.isEmpty {
                    Terminal.status("      reply: \(result.reply)")
                }
            }
        }

        Terminal.status(ReportFormatter.summary(record))

        if save {
            let url = Paths.newResultsFile(commit: record.gitCommit)
            try FileManager.default.createDirectory(at: Paths.resultsDirectory, withIntermediateDirectories: true)
            try record.jsonData().write(to: url)
            Terminal.status("Saved \(url.path)")
        }

        if strict, record.passRate < 1 {
            throw ExitCode.failure
        }
    }
}
