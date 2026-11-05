//
//  CompareCommand.swift
//  CoachEval
//
//  Diffs two saved runs — the A/B step of prompt iteration.
//

import ArgumentParser
import Foundation
import CoachEvalKit

struct CompareCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "compare",
        abstract: "Compare per-scenario pass rates of two saved runs.",
        discussion: "With no arguments, compares the two most recent runs in Evals/results/."
    )

    @Argument(help: "The earlier run's JSON file.")
    var before: String?

    @Argument(help: "The later run's JSON file.")
    var after: String?

    func run() throws {
        let (beforeURL, afterURL) = try resolveFiles()
        let beforeRecord = try RunRecord.decode(Data(contentsOf: beforeURL))
        let afterRecord = try RunRecord.decode(Data(contentsOf: afterURL))
        let rows = RunComparison.rows(before: beforeRecord, after: afterRecord)
        print(ReportFormatter.comparison(rows, before: beforeRecord, after: afterRecord))
        if beforeRecord.samplesPerScenario < 5 || afterRecord.samplesPerScenario < 5 {
            print("\nNote: with fewer than 5 samples per scenario, a one-sample swing moves a rate by 20%+. Treat small changes as noise.")
        }
    }

    /// The two files to compare: as given, or the latest two saved runs.
    private func resolveFiles() throws -> (URL, URL) {
        switch (before, after) {
        case let (before?, after?):
            return (URL(fileURLWithPath: before), URL(fileURLWithPath: after))
        case (nil, nil):
            let saved = (try? FileManager.default.contentsOfDirectory(
                at: Paths.resultsDirectory, includingPropertiesForKeys: nil
            ))?.filter { $0.pathExtension == "json" }
                .sorted { $0.lastPathComponent < $1.lastPathComponent } ?? []
            guard saved.count >= 2 else {
                throw ValidationError("Need two saved runs in \(Paths.resultsDirectory.path); use `run --save`.")
            }
            return (saved[saved.count - 2], saved[saved.count - 1])
        default:
            throw ValidationError("Pass two files, or none to compare the latest two saved runs.")
        }
    }
}
