//
//  HomeStrengthRow.swift
//  Hybrid AIthletics
//
//  Compact row for one of today's strength exercises on the Home tab.
//
//  Deliberately not `StrengthExerciseCard`: that card owns drag-and-drop,
//  move-to-day, and offload affordances, which are weekly-board semantics and
//  don't belong on a "what am I doing today" surface. Tapping here records.
//

import SwiftUI

/// One of today's strength exercises, tappable to record a weight.
struct HomeStrengthRow: View {
    let exercise: StrengthExercise
    /// Called when the row is tapped to record a weight entry.
    let onRecord: () -> Void

    @Environment(\.useMetricUnits) private var useMetricUnits

    var body: some View {
        Button(action: onRecord) {
            HStack(spacing: 12) {
                Image(systemName: "dumbbell.fill")
                    .font(.callout)
                    .foregroundStyle(exercise.muscleGroup.color)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 2) {
                    Text(exercise.name)
                        .font(.subheadline.weight(.medium))
                        .foregroundStyle(.primary)
                    HStack(spacing: 6) {
                        Text(exercise.muscleGroup.rawValue)
                        if let plan = exercise.plannedSummary {
                            Text("•")
                            Text(plan)
                        }
                    }
                    .font(.caption)
                    .foregroundStyle(.secondary)
                }

                Spacer()

                if let latest = exercise.latestWorkout {
                    Text(latest.weightPounds.formattedWeight(metric: useMetricUnits))
                        .font(.caption.weight(.semibold))
                        .foregroundStyle(.secondary)
                }

                Image(systemName: "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.tertiary)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color(.secondarySystemGroupedBackground))
            )
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.strengthRow.\(exercise.name)")
    }
}
