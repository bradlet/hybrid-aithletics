//
//  ListCommand.swift
//  CoachEval
//
//  Lists the scenario library.
//

import ArgumentParser
import CoachEvalKit

struct ListCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "list",
        abstract: "List scenarios and tags."
    )

    @Flag(name: .long, help: "Also print each scenario's summary and checks.")
    var details = false

    func run() {
        let width = ScenarioLibrary.all.map(\.id.count).max() ?? 0
        for scenario in ScenarioLibrary.all {
            let tags = scenario.tags.sorted().joined(separator: ", ")
            print("\(scenario.id.padding(toLength: width, withPad: " ", startingAt: 0))  \(scenario.title)  [\(tags)]")
            if details {
                print("    \(scenario.summary)")
                print("    athlete: \"\(scenario.athleteMessage)\"")
                for expectation in scenario.expectations {
                    print("    • \(expectation.label)")
                }
                print("")
            }
        }
        print("\nTags: \(ScenarioLibrary.tags.joined(separator: ", "))")
    }
}
