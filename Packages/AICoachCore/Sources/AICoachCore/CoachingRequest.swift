//
//  CoachingRequest.swift
//  AICoachCore
//
//  Value type describing the inputs to the AI coach: recent training
//  history and upcoming planned exercises.
//

import Foundation

/// Inputs to the AI coach: the athlete's recent training history and
/// their upcoming planned training.
///
/// Conforms to `Identifiable` so it can drive SwiftUI `.sheet(item:)`
/// presentations directly.
public struct CoachingRequest: Identifiable, Sendable {
    /// Stable identity used by SwiftUI sheet presentation.
    public let id: UUID
    /// Completed workouts from the lookback window, chronologically ordered.
    public let recentWorkouts: [CoachWorkout]
    /// Planned exercises in the forward-looking window, chronologically ordered.
    public let upcomingExercises: [CoachExercise]
    /// The weekly strength board, in board order (day, section, position).
    /// Defaults to empty so callers without strength data are unaffected.
    public let strengthExercises: [CoachStrengthExercise]
    /// Whether to render distances in kilometers (true) or miles (false).
    public let useMetricUnits: Bool

    public init(
        id: UUID = UUID(),
        recentWorkouts: [CoachWorkout],
        upcomingExercises: [CoachExercise],
        strengthExercises: [CoachStrengthExercise] = [],
        useMetricUnits: Bool
    ) {
        self.id = id
        self.recentWorkouts = recentWorkouts
        self.upcomingExercises = upcomingExercises
        self.strengthExercises = strengthExercises
        self.useMetricUnits = useMetricUnits
    }
}
