//
//  CoachEntryCard.swift
//  Hybrid AIthletics
//
//  The Home tab's entry point into the coach conversation. Replaces the
//  "Ask Coach" toolbar button that used to open a one-shot sheet.
//

import SwiftUI

/// Tappable card that opens the coach chat, previewing the live conversation.
///
/// Reflects model availability so the gating is visible from Home rather than
/// discovered after tapping through: until the weights are downloaded the card
/// is dimmed and reads as a call to action.
struct CoachEntryCard: View {
    /// The tail of the last coach reply this session, or nil for a fresh start.
    let lastReply: String?
    /// Whether a turn is currently generating.
    let isGenerating: Bool
    /// The model's availability, which decides how the card presents itself.
    let phase: CoachModelPhase

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: glyph)
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(isAvailable ? Color.accentColor : Color.secondary)
                .frame(width: 44, height: 44)
                .background(
                    Circle().fill(
                        (isAvailable ? Color.accentColor : Color.secondary).opacity(0.15)
                    )
                )

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Coach")
                        .font(.headline)
                        .foregroundStyle(isAvailable ? .primary : .secondary)
                    if isGenerating {
                        ProgressView().controlSize(.mini)
                    }
                    if case .downloading(let progress) = phase {
                        if let fraction = progress.fraction {
                            Text("\(Int(fraction * 100))%")
                                .font(.caption.monospacedDigit())
                                .foregroundStyle(.secondary)
                        } else {
                            ProgressView().controlSize(.mini)
                        }
                    }
                }
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
            }

            Spacer(minLength: 8)

            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(.tertiary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 16, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        // Dimmed while the coach can't actually answer, so an unusable feature
        // doesn't look live.
        .opacity(isAvailable ? 1 : 0.55)
    }

    /// Whether tapping the card will get the athlete a working coach.
    private var isAvailable: Bool { phase.isUsable }

    /// Download affordance when the weights are missing, sparkles otherwise.
    private var glyph: String {
        phase.needsDownload ? "arrow.down.circle" : "sparkles"
    }

    /// Shows where the conversation left off, so returning to Home reads as
    /// continuity rather than a reset — or what is blocking the coach.
    private var subtitle: String {
        switch phase {
        case .notDownloaded:
            return "Tap to download the model and enable AI coaching"
        case .failed:
            return "Download didn't finish — tap to try again"
        case .downloading:
            return "Downloading the model…"
        case .loadingIntoMemory:
            return "Starting up…"
        case .downloaded, .unknown, .ready:
            if let lastReply, !lastReply.isEmpty {
                return lastReply
            }
            return "Ask about your training"
        }
    }
}
