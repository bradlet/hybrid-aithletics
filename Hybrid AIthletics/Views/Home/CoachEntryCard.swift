//
//  CoachEntryCard.swift
//  Hybrid AIthletics
//
//  The Home tab's entry point into the coach conversation. Replaces the
//  "Ask Coach" toolbar button that used to open a one-shot sheet.
//

import SwiftUI

/// Tappable card that opens the coach chat, previewing the live conversation.
struct CoachEntryCard: View {
    /// The tail of the last coach reply this session, or nil for a fresh start.
    let lastReply: String?
    /// Whether a turn is currently generating.
    let isGenerating: Bool

    var body: some View {
        HStack(spacing: 14) {
            Image(systemName: "sparkles")
                .font(.title2)
                .symbolRenderingMode(.hierarchical)
                .foregroundStyle(Color.accentColor)
                .frame(width: 44, height: 44)
                .background(Circle().fill(Color.accentColor.opacity(0.15)))

            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text("Coach")
                        .font(.headline)
                        .foregroundStyle(.primary)
                    if isGenerating {
                        ProgressView().controlSize(.mini)
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
        .accessibilityIdentifier("home.coachCard")
    }

    /// Shows where the conversation left off, so returning to Home reads as
    /// continuity rather than a reset.
    private var subtitle: String {
        if let lastReply, !lastReply.isEmpty {
            return lastReply
        }
        return "Ask about your training"
    }
}
