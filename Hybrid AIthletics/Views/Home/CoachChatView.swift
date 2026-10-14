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
                    if case .loading(let fraction) = store.modelPhase {
                        modelLoadingCard(fraction: fraction)
                    }
                    if case .failed(let reason) = store.modelPhase {
                        noticeCard(reason, systemImage: "exclamationmark.triangle", tint: .red)
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

    /// Download / load progress. Copy carried over from the retired sheet,
    /// where it was already tuned for the ~2 GB first-run download.
    private func modelLoadingCard(fraction: Double?) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 10) {
                ProgressView()
                Text(coach.isModelCached ? "Loading model…" : "Downloading AI coach…")
                    .font(.callout)
                    .foregroundStyle(.secondary)
            }
            if let fraction {
                ProgressView(value: fraction).tint(.accentColor)
                Text("\(Int(fraction * 100))% — ~2 GB download, this only happens once.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            } else if !coach.isModelCached {
                Text("~2 GB download — this only happens once.")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
            }
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
    }

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
            Text("Ask about…")
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
    }

    private var composer: some View {
        HStack(spacing: 10) {
            TextField("Message your coach", text: $draft, axis: .vertical)
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
        case .reply: "text.bubble"
        }
    }

    private var title: String {
        switch action {
        case .recordWorkout: "Record this workout?"
        case .suggestScheduleChange: "Change your plan?"
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
        }
    }

    /// Cached per project convention.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEE, MMM d"
        return f
    }()
}
