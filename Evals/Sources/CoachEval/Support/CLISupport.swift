//
//  CLISupport.swift
//  CoachEval
//
//  Small pieces shared by the commands: sampling options, terminal output,
//  git metadata, and where results are saved.
//

import ArgumentParser
import Foundation
import AICoachCore

/// Sampling overrides, shared by `run` and `chat` via `@OptionGroup`.
///
/// Every option defaults to `GenerationConfig.chat` — what the app's
/// conversation uses — so an un-flagged run measures production settings.
struct GenerationOptions: ParsableArguments {

    @Option(help: "Sampling temperature (app: \(GenerationConfig.chat.temperature)).")
    var temperature: Float?

    @Option(help: "Nucleus sampling cutoff (app: \(GenerationConfig.chat.topP)).")
    var topP: Float?

    @Option(help: "Repetition penalty (app: \(GenerationConfig.chat.repetitionPenalty)).")
    var repetitionPenalty: Float?

    @Option(help: "Maximum tokens per turn (app: \(GenerationConfig.chat.maxTokens)).")
    var maxTokens: Int?

    /// `GenerationConfig.chat` with any overrides applied.
    var config: GenerationConfig {
        var config = GenerationConfig.chat
        if let temperature { config.temperature = temperature }
        if let topP { config.topP = topP }
        if let repetitionPenalty { config.repetitionPenalty = repetitionPenalty }
        if let maxTokens { config.maxTokens = maxTokens }
        return config
    }
}

/// Terminal output helpers.
enum Terminal {

    /// Prints and flushes immediately, so progress shows up while the model
    /// is busy rather than all at once when stdout's buffer fills.
    static func status(_ line: String) {
        print(line)
        fflush(stdout)
    }

    /// Prints without a newline and flushes — for streamed tokens.
    static func stream(_ text: String) {
        print(text, terminator: "")
        fflush(stdout)
    }
}

/// Git metadata recorded on saved runs.
enum Git {

    /// Short HEAD hash, suffixed `-dirty` when the tree has uncommitted
    /// changes (usually the prompt edit being evaluated). `nil` outside git.
    static func describeHead() -> String? {
        guard let hash = run(["rev-parse", "--short", "HEAD"]), !hash.isEmpty else { return nil }
        let dirty = !(run(["status", "--porcelain"]) ?? "").isEmpty
        return dirty ? "\(hash)-dirty" : hash
    }

    /// Runs `git` with `arguments` in the Evals directory; trimmed stdout, or `nil`.
    private static func run(_ arguments: [String]) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/git")
        process.arguments = arguments
        process.currentDirectoryURL = Paths.evalsDirectory
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }
        guard process.terminationStatus == 0 else { return nil }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Filesystem locations.
enum Paths {

    /// The `Evals/` directory, found from this source file's location so it
    /// is right whatever directory the tool is launched from.
    static let evalsDirectory: URL = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // Support
        .deletingLastPathComponent() // CoachEval
        .deletingLastPathComponent() // Sources
        .deletingLastPathComponent() // Evals

    /// Where `run --save` writes, git-ignored.
    static var resultsDirectory: URL {
        evalsDirectory.appendingPathComponent("results", isDirectory: true)
    }

    /// A fresh results file name: `20261014-153012-abc1234.json`.
    static func newResultsFile(commit: String?) -> URL {
        let stamp = stampFormatter.string(from: Date())
        let suffix = commit.map { "-\($0)" } ?? ""
        return resultsDirectory.appendingPathComponent("\(stamp)\(suffix).json")
    }

    /// Cached formatter for result file names.
    private static let stampFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd-HHmmss"
        return formatter
    }()
}
