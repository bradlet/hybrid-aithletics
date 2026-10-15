//
//  CoachChatStore.swift
//  Hybrid AIthletics
//
//  Session-scoped state for the coach conversation: the transcript, the
//  model's load phase, and any proposals awaiting the athlete's decision.
//
//  Deliberately ephemeral. The store lives in App scope and is exposed via
//  `@Environment(\.coachChat)`, so a conversation survives tab switches and
//  navigation pops but is gone on relaunch. This is the same shape as
//  `GoogleSheetsSyncCoordinator` — app-scope observable state, not a ViewModel:
//  it owns no SwiftData queries and makes no view decisions.
//

import Foundation
import Observation
import AICoachCore

/// Lifecycle of the on-device model, surfaced so the chat view can gate itself
/// and show real download progress.
enum CoachModelPhase: Equatable {
    /// Availability not checked yet.
    case unknown
    /// Weights are not on disk. The athlete has to opt into the download —
    /// it is multi-gigabyte, so it is never started implicitly.
    case notDownloaded
    /// Weights are being fetched. Progress is byte-weighted.
    case downloading(AICoachDownloadProgress)
    /// Weights are on disk but not yet in memory. The coach is usable — it
    /// just needs a moment on first use.
    case downloaded
    /// Weights are on disk and being loaded into memory. Fast and offline, so
    /// this needs no call to action.
    case loadingIntoMemory
    /// Loaded and ready to generate.
    case ready
    /// Download or load failed, with a user-facing reason.
    case failed(String)

    /// Whether the coach can be used right now.
    var isReady: Bool { self == .ready }

    /// Whether work is in flight, so the UI should not offer to start more.
    var isBusy: Bool {
        switch self {
        case .downloading, .loadingIntoMemory: true
        case .unknown, .notDownloaded, .downloaded, .ready, .failed: false
        }
    }

    /// Whether the athlete needs to trigger the download before anything works.
    var needsDownload: Bool {
        switch self {
        case .notDownloaded, .failed: true
        case .unknown, .downloading, .downloaded, .loadingIntoMemory, .ready: false
        }
    }

    /// Whether the coach will work if tapped — the weights exist, even if they
    /// still have to be read into memory. Drives whether the Home card is
    /// presented as live or dimmed.
    var isUsable: Bool {
        switch self {
        case .downloaded, .loadingIntoMemory, .ready: true
        case .unknown, .notDownloaded, .downloading, .failed: false
        }
    }
}

/// The conversation with the AI coach for the life of this app session.
@MainActor
@Observable
final class CoachChatStore {

    // MARK: - Public state

    /// The transcript, oldest first. Contains no `.system` turn — the prompt
    /// builder adds that at generation time.
    private(set) var messages: [CoachMessage] = []

    /// Proposals awaiting Accept or Dismiss, keyed by the coach message that
    /// carried them, so a bubble can render its own decision controls.
    private(set) var pendingProposals: [UUID: CoachAction] = [:]

    /// Whether a turn is currently generating.
    private(set) var isGenerating = false

    /// The model's load phase.
    private(set) var modelPhase: CoachModelPhase = .unknown

    /// The last generation error, cleared when a new turn starts.
    private(set) var errorMessage: String?

    /// Whether a training snapshot has already been attached to a turn.
    ///
    /// Drives snapshot-once-per-conversation: re-sending the athlete's training
    /// data on every turn would spend a large share of a 4B model's context
    /// window restating what the transcript already carries.
    private(set) var hasAttachedContext = false

    /// The in-flight generation, retained so `cancel()` can stop it.
    private var generationTask: Task<Void, Never>?

    // MARK: - Derived state

    /// Whether the athlete can send a message right now.
    var canSend: Bool { modelPhase.isReady && !isGenerating }

    /// The tail of the last coach reply, for the Home entry card's preview.
    var lastCoachReply: String? {
        let text = messages.last { $0.role == .coach }?.text
            .trimmingCharacters(in: .whitespacesAndNewlines)
        return (text?.isEmpty ?? true) ? nil : text
    }

    // MARK: - Model lifecycle

    /// Records whether the weights are on disk. Touches the filesystem only —
    /// it downloads nothing and loads nothing.
    ///
    /// Home calls this on appearance so its coach card can present itself
    /// honestly. It deliberately does **not** load the model: Home is the
    /// landing tab, and pulling 4.3 GB of weights into memory on every launch
    /// for a feature the athlete may not open would spike memory and slow the
    /// launch for nothing.
    /// - Parameter coach: The service to inspect.
    func checkAvailability(coach: AICoachService) {
        guard !modelPhase.isReady, !modelPhase.isBusy else { return }
        // Don't clobber a failure the athlete hasn't seen yet.
        if case .failed = modelPhase { return }
        modelPhase = coach.isModelCached ? .downloaded : .notDownloaded
    }

    /// Loads already-downloaded weights into memory, so the chat is usable.
    ///
    /// Called when the chat appears. When the weights are missing it stops at
    /// `.notDownloaded` so the athlete is asked first — silently starting a
    /// multi-gigabyte download on someone's cellular connection is not a
    /// reasonable default.
    /// - Parameter coach: The service to load.
    func prepareModel(coach: AICoachService) async {
        guard !modelPhase.isReady, !modelPhase.isBusy else { return }
        guard coach.isModelCached else {
            if case .failed = modelPhase { return }
            modelPhase = .notDownloaded
            return
        }
        await load(coach: coach, startingAt: .loadingIntoMemory)
    }

    /// Starts the download, then loads the model. Call only from an explicit
    /// athlete action.
    /// - Parameter coach: The service to download and load.
    func downloadModel(coach: AICoachService) async {
        guard !modelPhase.isReady, !modelPhase.isBusy else { return }
        let initial = AICoachDownloadProgress(
            completedBytes: 0,
            totalBytes: coach.approximateDownloadBytes
        )
        await load(coach: coach, startingAt: .downloading(initial))
    }

    /// Shared download/load body.
    private func load(coach: AICoachService, startingAt phase: CoachModelPhase) async {
        modelPhase = phase

        var mutableCoach = coach
        mutableCoach.onDownloadProgress = { [weak self] progress in
            Task { @MainActor [weak self] in
                guard let self, self.modelPhase.isBusy else { return }
                self.modelPhase = .downloading(progress)
            }
        }

        do {
            try await mutableCoach.loadModel()
            modelPhase = .ready
        } catch {
            modelPhase = .failed(error.localizedDescription)
        }
    }

    // MARK: - Sending

    /// Appends the athlete's message and streams the coach's reply into the
    /// transcript.
    ///
    /// - Parameters:
    ///   - text: What the athlete typed. Blank input is ignored.
    ///   - coach: The service to generate with.
    ///   - context: Builds the training snapshot. An autoclosure so the
    ///     caller only pays for assembling it on the turn that attaches it.
    func send(
        _ text: String,
        coach: AICoachService,
        context: @autoclosure @escaping () -> CoachingRequest
    ) async {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty, !isGenerating else { return }

        errorMessage = nil
        messages.append(CoachMessage(role: .user, text: trimmed))

        let coachTurn = CoachMessage(role: .coach)
        messages.append(coachTurn)

        // Attach the snapshot only on the first turn of the conversation.
        let attachingContext = !hasAttachedContext
        let request = CoachChatRequest(
            messages: messages.dropLast().map { $0 },
            context: attachingContext ? context() : nil
        )

        isGenerating = true
        let task = Task { @MainActor in
            await self.stream(request, from: coach, into: coachTurn.id)
        }
        generationTask = task
        await task.value

        // Only now is the data genuinely in the transcript the model has seen;
        // marking it earlier would silently drop it if the first turn failed.
        if attachingContext, errorMessage == nil, !Task.isCancelled {
            hasAttachedContext = true
        }
        isGenerating = false
        generationTask = nil
    }

    /// Folds a generation stream into the transcript.
    private func stream(
        _ request: CoachChatRequest,
        from coach: AICoachService,
        into coachTurnID: UUID
    ) async {
        do {
            for try await event in coach.streamChat(request) {
                if Task.isCancelled { return }
                switch event {
                case .textChunk(let chunk):
                    append(chunk, to: coachTurnID)
                case .action(.reply(let text)):
                    append(text, to: coachTurnID)
                case .action(let action):
                    // First proposal of the turn wins. A small model routinely
                    // emits the same call two or three times in one pass, each
                    // slightly different; overwriting made the proposal card
                    // visibly rewrite itself and left the athlete approving
                    // whichever version happened to land last.
                    guard pendingProposals[coachTurnID] == nil else { continue }
                    pendingProposals[coachTurnID] = action
                case .rejectedToolCall(let reason):
                    // Surfaced rather than swallowed: silence would be
                    // indistinguishable from the coach having nothing to say.
                    // Phrased as a request rather than a failure because the
                    // common rejection is a call made before the athlete had
                    // given every value — the recovery is them filling it in.
                    append(
                        "\n\n_I started to suggest something there but didn\'t have "
                            + "it right (\(reason)) — could you tell me the details again?_",
                        to: coachTurnID
                    )
                }
            }
        } catch is CancellationError {
            // Stopping is a deliberate user action, not an error to report.
        } catch {
            errorMessage = error.localizedDescription
        }
        pruneEmptyTurn(coachTurnID)
    }

    /// Appends streamed text to the coach turn still being generated.
    private func append(_ chunk: String, to id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        messages[index].text += chunk
    }

    /// Drops a coach turn that produced neither text nor a proposal, so a
    /// failed or empty generation doesn't leave a blank bubble behind.
    private func pruneEmptyTurn(_ id: UUID) {
        guard let index = messages.firstIndex(where: { $0.id == id }) else { return }
        let isEmpty = messages[index].text
            .trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        if isEmpty, pendingProposals[id] == nil {
            messages.remove(at: index)
        }
    }

    // MARK: - Proposals

    /// The proposal awaiting a decision on the given coach turn, if any.
    func proposal(for messageID: UUID) -> CoachAction? {
        pendingProposals[messageID]
    }

    /// Clears a proposal once it has been accepted or dismissed.
    ///
    /// Accepting is the caller's job: applying a schedule change needs a
    /// `ModelContext`, and a workout proposal opens the record sheet. The store
    /// only tracks what is still undecided.
    func resolveProposal(for messageID: UUID) {
        pendingProposals.removeValue(forKey: messageID)
    }

    /// Records that a proposal was acted on, appending a short confirmation so
    /// the transcript reflects what happened.
    func confirmProposal(for messageID: UUID, note: String) {
        resolveProposal(for: messageID)
        messages.append(CoachMessage(role: .coach, text: note))
    }

    // MARK: - Lifecycle

    /// Stops an in-flight generation, keeping whatever text already arrived.
    func cancel() {
        generationTask?.cancel()
        generationTask = nil
        isGenerating = false
    }

    /// Resets the conversation.
    ///
    /// Also re-arms the training snapshot, so the next question carries fresh
    /// data rather than relying on a transcript that no longer exists.
    func clear() {
        cancel()
        messages.removeAll()
        pendingProposals.removeAll()
        errorMessage = nil
        hasAttachedContext = false
    }
}
