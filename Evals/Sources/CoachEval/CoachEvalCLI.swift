//
//  CoachEvalCLI.swift
//  CoachEval
//
//  Entry point for `coach-eval`, the AI coach's eval and playground tool.
//

import ArgumentParser

@main
struct CoachEvalCLI: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "coach-eval",
        abstract: "Evaluate and explore the AI coach against the production model on Metal.",
        discussion: "Start with `list`, then `inspect`, `chat`, and `run`. See docs/EVALS_GUIDE.md.",
        subcommands: [
            RunCommand.self,
            ChatCommand.self,
            InspectPromptCommand.self,
            CompareCommand.self,
            ListCommand.self,
        ],
        defaultSubcommand: ListCommand.self
    )
}
