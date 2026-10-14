//
//  TodayTrainingSection.swift
//  Hybrid AIthletics
//
//  The "today" block on the Home tab: the day's aerobic sessions and the day's
//  active strength lane. Selection and ordering live in `TodayTraining`; this
//  file is presentation only.
//

import SwiftUI

/// Today's aerobic and strength work, with one-tap recording.
struct TodayTrainingSection: View {
    /// Today's aerobic exercises, already ordered by `TodayTraining.aerobic`.
    let aerobic: [Exercise]
    /// Today's active strength lane, already ordered by `TodayTraining.strength`.
    let strength: [StrengthExercise]
    /// Called to record (or re-open) an aerobic exercise.
    let onRecordAerobic: (Exercise) -> Void
    /// Called to edit an aerobic exercise's plan or recorded data.
    let onEditAerobic: (Exercise) -> Void
    /// Called to record a weight against a strength exercise.
    let onRecordStrength: (StrengthExercise) -> Void

    /// Shared across the aerobic cards so only one shows its delete button.
    @State private var swipeDeleteActiveID: UUID?

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            header

            if TodayTraining.isEmpty(aerobic: aerobic, strength: strength) {
                emptyState
            } else {
                if !aerobic.isEmpty {
                    VStack(spacing: 8) {
                        ForEach(aerobic) { exercise in
                            ExerciseCardView(
                                exercise: exercise,
                                onRecord: { onRecordAerobic(exercise) },
                                onEdit: { onEditAerobic(exercise) },
                                hasRecordedWorkout: exercise.isCompleted,
                                swipeDeleteActiveID: $swipeDeleteActiveID
                            )
                        }
                    }
                }

                if !strength.isEmpty {
                    if !aerobic.isEmpty {
                        Text("Strength")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.secondary)
                            .padding(.top, 4)
                    }
                    VStack(spacing: 8) {
                        ForEach(strength) { exercise in
                            HomeStrengthRow(exercise: exercise) {
                                onRecordStrength(exercise)
                            }
                        }
                    }
                }
            }
        }
    }

    // MARK: - Subviews

    private var header: some View {
        HStack {
            Text("Today")
                .font(.headline)
            Spacer()
            Text(Self.dayFormatter.string(from: Date()))
                .font(.subheadline)
                .foregroundStyle(.secondary)
        }
        .accessibilityIdentifier("home.todayHeader")
    }

    private var emptyState: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label("Nothing scheduled today", systemImage: "calendar")
                .font(.subheadline.weight(.medium))
            Text("Log something below, or plan ahead from the Training tab.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding()
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .fill(Color(.secondarySystemGroupedBackground))
        )
        .accessibilityIdentifier("home.todayEmpty")
    }

    /// Cached per project convention — never allocate in a computed property.
    private static let dayFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "EEEE, MMM d"
        return f
    }()
}
