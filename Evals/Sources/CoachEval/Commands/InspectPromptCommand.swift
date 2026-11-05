//
//  InspectPromptCommand.swift
//  CoachEval
//
//  Prints the raw prompt for a scenario without running the model.
//  Useful for iterating on prompt text without waiting for generation.
//

import ArgumentParser
import Foundation
import AICoachCore

struct InspectPromptCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "inspect",
        abstract: "Print the raw prompt for a scenario (no model needed)."
    )

    @Option(name: .long, help: "Scenario ID to inspect.")
    var scenario: String = "high-rpe"

    func run() async throws {
        guard let s = ScenarioLibrary.scenario(id: scenario) else {
            print("Error: Unknown scenario '\(scenario)'. Available: \(ScenarioLibrary.all.map(\.id).joined(separator: ", "))")
            throw ExitCode.validationFailure
        }
        printConversation(scenario: s)
    }

    /// Prints what the tool-calling coach actually sees: the conversational
    /// system preamble, the athlete's first turn with the training snapshot
    /// attached, and the tool schemas the chat template renders from.
    private func printConversation(scenario s: EvalScenario) {
        let today = Date()
        let divider = String(repeating: "=", count: 60)
        print(divider)
        print("Scenario: \(s.id) (\(s.name))")
        print(divider)

        let request = CoachChatRequest(
            messages: [CoachMessage(role: .user, text: AICoachPromptBuilder.closingQuestion)],
            context: s.request
        )
        for turn in AICoachPromptBuilder.buildChatTurns(for: request, today: today) {
            print("\n[\(turn.role.rawValue) message]")
            print(turn.text)
        }

        print("\n[Tool schemas]")
        let tools = CoachToolSchemas.all(today: today)
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
