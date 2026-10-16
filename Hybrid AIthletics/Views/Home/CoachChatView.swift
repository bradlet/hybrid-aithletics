//
//  CoachChatView.swift
//  Hybrid AIthletics
//
//  The coach conversation. A pushed destination rather than a sheet so the
//  keyboard and the pinned composer behave.
//
//  Replaces the one-shot AICoachSheet: the old sheet's single question is now
//  one of the suggested prompts.
//

import SwiftUI
import AICoachCore

/// Multi-turn conversation with the on-device coach.
struct CoachChatView: View {
    @Environment(\.aiCoach) private var coach
    @Environment(\.coachChat) private var store

    /// Builds the training snapshot. Called at most once per conversation.
    let buildContext: () -> CoachingRequest
    /// Called when the athlete accepts a workout proposal.
    let onAcceptWorkout: (WorkoutProposal, UUID) -> Void
    /// Called when the athlete accepts a schedule-change proposal.
    let onAcceptScheduleChange: (ScheduleChangeProposal, UUID) -> Void
    /// Called when the athlete accepts a strength-day proposal.
    let onAcceptStrengthDay: (StrengthDayProposal, UUID) -> Void

    @State private var draft: String = ""

    /// Prompts offered on an empty transcript. The first is the question the
    /// retired one-shot sheet asked, verbatim.
    private static let suggestions = [
        "What should change about my upcoming plan?",
        "Am I ramping up too fast?",
        "How did last week go?",
    ]

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 14) {
                    switch store.modelPhase {
                    case .notDownloaded:
                        downloadCallToAction(retrying: false)
                    case .failed(let reason):
                        noticeCard(reason, systemImage: "exclamationmark.triangle", tint: .red)
                        downloadCallToAction(retrying: true)
                    case .downloading(let progress):
                        downloadProgressCard(progress)
                    case .downloaded, .loadingIntoMemory:
                        loadingIntoMemoryCard
                    case .unknown, .ready:
                        EmptyView()
                    }

                    if store.messages.isEmpty {
                        suggestionChips
                    }

                    ForEach(store.messages) { message in
                        CoachMessageBubble(
                            message: message,
                            proposal: store.proposal(for: message.id),
                            onAccept: { accept($0, from: message.id) },
                            onDismiss: { store.resolveProposal(for: message.id) }
                        )
                        .id(message.id)
                    }

                    if let errorMessage = store.errorMessage {
                        noticeCard(
                            errorMessage,
                            systemImage: "exclamationmark.triangle",
                            tint: .red
                        )
                    }
                }
                .padding()
            }
            .onChange(of: store.messages.last?.text) { _, _ in
                guard let lastID = store.messages.last?.id else { return }
                withAnimation(.easeOut(duration: 0.2)) {
                    proxy.scrollTo(lastID, anchor: .bottom)
                }
            }
            .onChange(of: store.messages.count) { _, _ in
                guard let lastID = store.messages.last?.id else { return }
                proxy.scrollTo(lastID, anchor: .bottom)
            }
        }
        .background(Color(.systemGroupedBackground))
        .navigationTitle("Coach")
        .navigationBarTitleDisplayMode(.inline)
        .safeAreaInset(edge: .bottom) { composer }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                if store.isGenerating {
                    Button {
                        store.cancel()
                    } label: {
                        Label("Stop", systemImage: "stop.circle")
                    }
                    .accessibilityIdentifier("coach.chat.stop")
                } else if !store.messages.isEmpty {
                    Button {
                        store.clear()
                    } label: {
                        Label("Clear", systemImage: "trash")
                    }
                    .accessibilityIdentifier("coach.chat.clear")
                }
            }
        }
        .task { await store.prepareModel(coach: coach) }
    }

    // MARK: - Subviews

    /// Pre-download call to action. The coach does nothing until the athlete
    /// opts in, because the download is multi-gigabyte.
    private func downloadCallToAction(retrying: Bool) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 12) {
                Image(systemName: "arrow.down.circle")
                    .font(.title2)
                    .symbolRenderingMode(.hierarchical)
                    .foregroundStyle(Color.accentColor)
                VStack(alignment: .leading, spacing: 2) {
                    Text(retrying ? "Try the download again" : "Enable your AI coach")
                        .font(.headline)
                    Text("The coach runs entirely on your device. Its model has to be downloaded once before chat works.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Button {
                Task { await store.downloadModel(coach: coach) }
            } label: {
                Label(
                    "Download\(downloadSizeSuffix)",
                    systemImage: "arrow.down.circle.fill"
                )
                .frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .controlSize(.large)
            .accessibilityIdentifier("coach.chat.download")

            Text("Best over Wi-Fi. You can keep using the rest of the app while it downloads.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        // `.contain` makes the container queryable; the identifier alone
        // only groups its children and no element matches.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.chat.downloadPrompt")
    }

    /// Live download progress, weighted by bytes rather than file count.
    private func downloadProgressCard(_ progress: AICoachDownloadProgress) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                Text("Downloading your AI coach")
                    .font(.callout.weight(.medium))
                Spacer()
                if let fraction = progress.fraction {
                    Text("\(Int(fraction * 100))%")
                        .font(.callout.monospacedDigit())
                        .foregroundStyle(.secondary)
                }
            }

            if let fraction = progress.fraction {
                ProgressView(value: fraction).tint(.accentColor)
            } else {
                ProgressView().progressViewStyle(.linear)
            }

            Text(Self.byteProgressDescription(progress))
                .font(.caption)
                .foregroundStyle(.secondary)
                .monospacedDigit()

            if let rate = Self.rateDescription(progress) {
                Text(rate)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
            }

            Text("This only happens once. Leaving this screen won't cancel it.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        // `.contain` makes the container queryable; the identifier alone
        // only groups its children and no element matches.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.chat.downloadProgress")
    }

    /// Weights are on disk; this is the quick, offline load into memory.
    private var loadingIntoMemoryCard: some View {
        HStack(spacing: 10) {
            ProgressView()
            Text("Starting your coach…")
                .font(.callout)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        // `.contain` makes the container queryable; the identifier alone
        // only groups its children and no element matches.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.chat.loading")
    }

    /// " (4.4 GB)" when a size is known, else "".
    private var downloadSizeSuffix: String {
        let bytes = coach.approximateDownloadBytes
        guard bytes > 0 else { return "" }
        return " (\(Self.byteFormatter.string(fromByteCount: bytes)))"
    }

    /// e.g. "1.2 GB of 4.4 GB".
    static func byteProgressDescription(_ progress: AICoachDownloadProgress) -> String {
        let done = byteFormatter.string(fromByteCount: progress.completedBytes)
        guard progress.totalBytes > 0 else { return done }
        return "\(done) of \(byteFormatter.string(fromByteCount: progress.totalBytes))"
    }

    /// e.g. "3.4 MB/s — about 15 min left", or `nil` before a rate can be
    /// measured.
    ///
    /// This is the line that answers "has it hung?". A 4.3 GB download over a
    /// weak connection can spend minutes inside a single percent, and a bar
    /// alone cannot distinguish that from a dead transfer.
    static func rateDescription(_ progress: AICoachDownloadProgress) -> String? {
        guard let rate = progress.bytesPerSecond, rate > 0 else { return nil }
        var text = "\(byteFormatter.string(fromByteCount: Int64(rate)))/s"
        if let remaining = progress.estimatedSecondsRemaining,
           let formatted = remainingFormatter.string(from: remaining) {
            text += " — about \(formatted) left"
        }
        return text
    }

    /// Cached per project convention.
    static let byteFormatter: ByteCountFormatter = {
        let f = ByteCountFormatter()
        f.countStyle = .file
        f.allowedUnits = [.useMB, .useGB]
        return f
    }()

    /// Cached per project convention. Coarse on purpose — a smoothed rate does
    /// not justify advertising seconds.
    static let remainingFormatter: DateComponentsFormatter = {
        let f = DateComponentsFormatter()
        f.allowedUnits = [.hour, .minute]
        f.unitsStyle = .short
        f.maximumUnitCount = 2
        f.zeroFormattingBehavior = .dropAll
        return f
    }()

    private func noticeCard(
        _ text: String,
        systemImage: String,
        tint: Color
    ) -> some View {
        Label(text, systemImage: systemImage)
            .font(.callout)
            .foregroundStyle(tint)
            .padding()
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
    }

    private var suggestionChips: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(store.canSend ? "Ask about…" : "Once your coach is ready, ask about…")
                .font(.caption.weight(.semibold))
                .foregroundStyle(.secondary)
            ForEach(Self.suggestions, id: \.self) { suggestion in
                Button {
                    send(suggestion)
                } label: {
                    Text(suggestion)
                        .font(.subheadline)
                        .multilineTextAlignment(.leading)
                        .padding(.vertical, 10)
                        .padding(.horizontal, 14)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            RoundedRectangle(cornerRadius: 12, style: .continuous)
                                .fill(Color(.secondarySystemGroupedBackground))
                        )
                }
                .buttonStyle(.plain)
                .disabled(!store.canSend)
            }
        }
        // Greyed out until the model is downloaded and loaded, so the gating is
        // visible rather than only felt on tap.
        .opacity(store.canSend ? 1 : 0.4)
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField(composerPrompt, text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .textFieldStyle(.plain)
                .padding(.vertical, 8)
                .padding(.horizontal, 12)
                .background(
                    RoundedRectangle(cornerRadius: 18, style: .continuous)
                        .fill(Color(.secondarySystemGroupedBackground))
                )
                .submitLabel(.send)
                .onSubmit { send(draft) }
                .disabled(!store.canSend)
                .accessibilityIdentifier("coach.chat.input")

            Button {
                send(draft)
            } label: {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title2)
            }
            .disabled(!canSendDraft)
            .accessibilityIdentifier("coach.chat.send")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
        .opacity(store.canSend ? 1 : 0.5)
    }

    /// Placeholder text that explains why the composer is inert.
    private var composerPrompt: String {
        switch store.modelPhase {
        case .notDownloaded, .failed: "Download the coach to start chatting"
        case .downloading: "Downloading your coach…"
        case .downloaded, .loadingIntoMemory, .unknown: "Starting your coach…"
        case .ready: "Message your coach"
        }
    }

    /// Whether the composer's send button is live.
    private var canSendDraft: Bool {
        store.canSend && !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    // MARK: - Actions

    private func send(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard store.canSend, !trimmed.isEmpty else { return }
        draft = ""
        Task {
            await store.send(trimmed, coach: coach, context: buildContext())
        }
    }

    /// Routes an accepted proposal to the Home tab, which owns the model context.
    private func accept(_ action: CoachAction, from messageID: UUID) {
        switch action {
        case .recordWorkout(let proposal):
            // Resolved when the record sheet saves, not here — the athlete is
            // still one confirmation away.
            store.resolveProposal(for: messageID)
            onAcceptWorkout(proposal, messageID)
        case .suggestScheduleChange(let proposal):
            onAcceptScheduleChange(proposal, messageID)
        case .planStrengthDay(let proposal):
            onAcceptStrengthDay(proposal, messageID)
        case .reply:
            store.resolveProposal(for: messageID)
        }
    }
}

// MARK: - Bubble

/// One turn in the transcript, plus its pending proposal when it has one.
struct CoachMessageBubble: View {
    let message: CoachMessage
    /// A proposal awaiting a decision on this turn, if any.
    let proposal: CoachAction?
    let onAccept: (CoachAction) -> Void
    let onDismiss: () -> Void

    @Environment(\.useMetricUnits) private var useMetricUnits

    private var isUser: Bool { message.role == .user }

    var body: some View {
        VStack(alignment: isUser ? .trailing : .leading, spacing: 8) {
            HStack {
                if isUser { Spacer(minLength: 32) }
                Text(message.text)
                    .font(.body)
                    .textSelection(.enabled)
                    .padding(.vertical, 10)
                    .padding(.horizontal, 14)
                    .background(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .fill(
                                isUser
                                    ? Color.accentColor.opacity(0.16)
                                    : Color(.secondarySystemGroupedBackground)
                            )
                    )
                if !isUser { Spacer(minLength: 32) }
            }

            if let proposal {
                ProposalCard(
                    action: proposal,
                    metric: useMetricUnits,
                    onAccept: { onAccept(proposal) },
                    onDismiss: onDismiss
                )
            }
        }
        .frame(maxWidth: .infinity, alignment: isUser ? .trailing : .leading)
        // `.contain` makes the container itself queryable; without it the
        // identifier only groups the children and no element matches.
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.chat.bubble.\(message.role.rawValue)")
    }
}

// MARK: - Proposal card

/// The Accept / Dismiss control for a coach proposal.
struct ProposalCard: View {
    let action: CoachAction
    let metric: Bool
    let onAccept: () -> Void
    let onDismiss: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.semibold))

            ForEach(details, id: \.self) { detail in
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            HStack(spacing: 10) {
                Button("Accept", action: onAccept)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                    .accessibilityIdentifier("coach.chat.accept")
                Button("Dismiss", action: onDismiss)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .accessibilityIdentifier("coach.chat.dismiss")
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.accentColor.opacity(0.10))
        )
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("coach.chat.proposal")
    }

    private var icon: String {
        switch action {
        case .recordWorkout: "square.and.pencil"
        case .suggestScheduleChange: "calendar.badge.clock"
        case .planStrengthDay: "dumbbell"
        case .reply: "text.bubble"
        }
    }

    private var title: String {
        switch action {
        case .recordWorkout: "Record this workout?"
        case .suggestScheduleChange: "Change your plan?"
        case .planStrengthDay: "Plan this strength day?"
        case .reply: "Suggestion"
        }
    }

    /// Human-readable summary lines, so the athlete can check what the coach
    /// heard before accepting.
    private var details: [String] {
        switch action {
        case .reply(let text):
            return [text]

        case .recordWorkout(let proposal):
            var lines = [
                "\(Self.dateFormatter.string(from: proposal.date)) · \(proposal.exerciseType.rawValue)"
            ]
            if let miles = proposal.distanceMiles {
                lines.append(miles.formattedDistance(metric: metric))
            }
            if let seconds = proposal.durationSeconds {
                lines.append(seconds.formattedDuration)
            }
            // Each rating is reported only when the coach actually heard it.
            if let exertion = proposal.perceivedExertion {
                lines.append("RPE \(exertion)/10")
            }
            if let feeling = proposal.feeling {
                lines.append("Felt \(FeelingVisuals.displayName(for: feeling))")
            }
            if let notes = proposal.notes, !notes.isEmpty {
                lines.append("“\(notes)”")
            }
            return lines

        case .suggestScheduleChange(let proposal):
            var lines = [Self.dateFormatter.string(from: proposal.date)]
            switch proposal.kind {
            case .adjustDistance:
                if let miles = proposal.distanceMiles {
                    lines.append("Distance → \(miles.formattedDistance(metric: metric))")
                }
            case .adjustDuration:
                if let seconds = proposal.durationSeconds {
                    lines.append("Duration → \(seconds.formattedDuration)")
                }
            case .changeType:
                if let type = proposal.exerciseType {
                    lines.append("Type → \(type.rawValue)")
                }
            case .remove:
                lines.append("Remove this session")
            case .add:
                if let type = proposal.exerciseType {
                    lines.append("Add a \(type.rawValue)")
                }
            }
            lines.append(proposal.rationale)
            return lines

        case .planStrengthDay(let proposal):
            var lines = [
                "\(proposal.weekdayName) · \(proposal.exercises.count) exercises"
            ]
            for exercise in proposal.exercises {
                var line = "\(exercise.name) — \(exercise.muscleGroup.rawValue)"
                if let sets = exercise.plannedSets, let reps = exercise.plannedReps {
                    line += ", \(sets)×\(reps)"
                }
                lines.append(line)
            }
            lines.append(proposal.rationale)
            return lines
        }
    }

    /// Cached per project convention.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}
