//
//  InspectPromptCommand.swift
//  CoachEval
//
//  Prints exactly what a scenario sends the model, without running it.
//  The fastest loop for prompt work: edit AICoachCore, re-run inspect.
//

import ArgumentParser
import Foundation
import AICoachCore
import CoachEvalKit

struct InspectPromptCommand: ParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Print a scenario's prompt turns and tool schemas (no model needed)."
    )

    @Option(name: .long, help: "Scenario id to inspect.")
    var scenario: String = "record-yesterday"

    @Flag(name: .long, help: "Omit the tool schemas (they are long and rarely change).")
    var noTools = false

    func run() throws {
        let s = try ScenarioLookup.require(scenario)
        let divider = String(repeating: "=", count: 60)
        print(divider)
        print("Scenario: \(s.id) — \(s.title)")
        print("Today:    \(EvalCalendar.label(s.today))")
        print(divider)

        // The same calls CoachRuntime.streamChat makes, so this is what the
        // chat template receives.
        for turn in AICoachPromptBuilder.buildChatTurns(for: s.chatRequest(), today: s.today) {
            print("\n[\(turn.role.rawValue) message]")
            print(turn.text)
        }

        guard !noTools else { return }
        print("\n[Tool schemas]")
        let tools = CoachToolSchemas.all(today: s.today)
        if JSONSerialization.isValidJSONObject(tools),
           let data = try? JSONSerialization.data(
               withJSONObject: tools, options: [.prettyPrinted, .sortedKeys]
           ),
           let json = String(data: data, encoding: .utf8) {
            print(json)
        }
        print("")
    }
}

/// Scenario lookup with a helpful error, shared by every command.
enum ScenarioLookup {

    /// The scenario with `id`, or a validation error listing the valid ids.
    static func require(_ id: String) throws -> EvalScenario {
        guard let scenario = ScenarioLibrary.scenario(id: id) else {
            throw ValidationError(
                "Unknown scenario '\(id)'. Available: \(ScenarioLibrary.all.map(\.id).joined(separator: ", "))"
            )
        }
        return scenario
    }
}
