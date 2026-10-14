//
//  QuickRecordSection.swift
//  Hybrid AIthletics
//
//  The quick-record entry point on the Home tab: log a workout or a lift
//  without first navigating to a calendar.
//

import SwiftUI

/// Two prominent buttons for recording today's work.
struct QuickRecordSection: View {
    /// Called to record an aerobic workout with no planned exercise behind it.
    let onLogWorkout: () -> Void
    /// Called to record a lift. The caller decides whether that means picking
    /// from today's lane or opening the exercise library.
    let onLogLift: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Quick Record")
                .font(.headline)

            HStack(spacing: 10) {
                quickButton(
                    title: "Log Workout",
                    systemImage: "figure.run",
                    identifier: "home.logWorkout",
                    action: onLogWorkout
                )
                quickButton(
                    title: "Log Lift",
                    systemImage: "dumbbell",
                    identifier: "home.logLift",
                    action: onLogLift
                )
            }
        }
    }

    private func quickButton(
        title: String,
        systemImage: String,
        identifier: String,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            VStack(spacing: 6) {
                Image(systemName: systemImage)
                    .font(.title3)
                Text(title)
                    .font(.subheadline.weight(.medium))
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 14)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.accentColor.opacity(0.12))
            )
            .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(identifier)
    }
}
