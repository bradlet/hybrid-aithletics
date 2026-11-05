//
//  CoachEvalCLI.swift
//  CoachEval
//
//  CLI entry point for the AI Coach evaluation tool.
//

import ArgumentParser

@main
struct CoachEvalCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "coach-eval",
        abstract: "Evaluate and iterate on the AI Coach's prompt and generation parameters.",
        subcommands: [
            InspectPromptCommand.self,
        ],
        defaultSubcommand: InspectPromptCommand.self
    )
}
