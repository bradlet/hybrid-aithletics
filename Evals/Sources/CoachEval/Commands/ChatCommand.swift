//
//  ChatCommand.swift
//  CoachEval
//
//  An interactive conversation with the production model in the terminal —
//  a playground for getting a feel for what the coach does with a prompt.
//

import ArgumentParser
import Foundation
import AICoachCore
import AICoachRuntime
import CoachEvalKit

struct ChatCommand: AsyncParsableCommand {
    static let configuration = CommandConfiguration(
        commandName: "chat",
        abstract: "Talk to the coach interactively, with a scenario's training snapshot.",
        discussion: """
        Commands inside the chat:
          /reset   start a new conversation (re-attaches the snapshot)
          /prompt  print the turns the next message would be sent with
          /quit    exit (Ctrl-D works too)
        """
    )

    @Option(name: .long, help: "Scenario whose snapshot to attach (see `list`).")
    var scenario: String = "record-yesterday"

    @Flag(name: .long, help: "Use the real date instead of the scenario's pinned date.")
    var realDate = false

    @Flag(name: .long, help: "Show raw events (chunks, actions, rejections) as they arrive.")
    var events = false

    @OptionGroup var generation: GenerationOptions

    func run() async throws {
        let base = try ScenarioLookup.require(scenario)
        let today = realDate ? Date() : base.today
        let runtime = try await ModelLoader.loadProduction()
        let config = generation.config

        Terminal.status("Chatting as of \(EvalCalendar.label(today)) with the \"\(base.id)\" snapshot. /quit to exit.\n")

        var conversation = Conversation(snapshot: base.snapshot)
        while true {
            Terminal.stream("you › ")
            guard let line = readLine() else { break }
            let text = line.trimmingCharacters(in: .whitespacesAndNewlines)
            switch text {
            case "":
                continue
            case "/quit", "/exit":
                return
            case "/reset":
                conversation = Conversation(snapshot: base.snapshot)
                Terminal.status("(new conversation)\n")
                continue
            case "/prompt":
                let preview = conversation.request(adding: "<your next message>")
                for turn in AICoachPromptBuilder.buildChatTurns(for: preview, today: today) {
                    Terminal.status("[\(turn.role.rawValue)]\n\(turn.text)\n")
                }
                continue
            default:
                break
            }

            let request = conversation.request(adding: text)
            Terminal.stream("coach › ")
            var transcript = TurnTranscript()
            let stats = StatsBox()
            do {
                for try await event in runtime.streamChat(request, today: today, config: config, onStats: { stats.value = $0 }) {
                    let hadProposal = transcript.proposal != nil
                    transcript.fold(event)
                    show(event, firstProposal: !hadProposal && transcript.proposal != nil)
                }
            } catch {
                Terminal.status("\n(error: \(error.localizedDescription))\n")
                continue
            }
            if let s = stats.value {
                Terminal.status(String(format: "\n   [%d prompt tokens, %d generated, %.0f tok/s]\n", s.promptTokens, s.generatedTokens, s.tokensPerSecond))
            }
            conversation.record(athlete: text, coach: transcript)
        }
    }

    /// Prints one event as it streams.
    private func show(_ event: CoachEvent, firstProposal: Bool) {
        if events {
            Terminal.status("\n   · \(event)")
        }
        switch event {
        case .textChunk(let text):
            if !events { Terminal.stream(text) }
        case .action(.reply(let text)):
            if !events { Terminal.stream(text) }
        case .action(let action):
            let marker = firstProposal ? "📋 proposal" : "   (ignored — first proposal wins)"
            Terminal.status("\n\(marker): \(ProposalSummary.describe(action))")
        case .rejectedToolCall(let reason):
            Terminal.status("\n⚠️  rejected tool call: \(reason)")
        }
    }
}

/// Conversation state, kept the way `CoachChatStore` keeps it.
///
/// The athlete's plain text and the coach's visible reply go into the
/// transcript; proposals do not. The snapshot is sent only with the first
/// request.
struct Conversation {
    private let snapshot: CoachingRequest?
    private var messages: [CoachMessage] = []
    private var hasAttachedSnapshot = false

    init(snapshot: CoachingRequest?) {
        self.snapshot = snapshot
    }

    /// The request for the athlete's next message.
    func request(adding text: String) -> CoachChatRequest {
        CoachChatRequest(
            messages: messages + [CoachMessage(role: .user, text: text)],
            context: hasAttachedSnapshot ? nil : snapshot
        )
    }

    /// Records a completed exchange. Like the store, a coach turn with neither
    /// text nor a proposal is dropped.
    mutating func record(athlete text: String, coach transcript: TurnTranscript) {
        messages.append(CoachMessage(role: .user, text: text))
        if !transcript.trimmedReply.isEmpty || transcript.proposal != nil {
            messages.append(CoachMessage(role: .coach, text: transcript.reply))
        }
        hasAttachedSnapshot = true
    }
}
