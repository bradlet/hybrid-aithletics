//
//  CoachStrengthExercise.swift
//  AICoachCore
//
//  Plain Codable snapshots of the strength board, mirroring the
//  CoachWorkout / CoachExercise pattern. The app converts its SwiftData
//  `StrengthExercise` models into these before constructing a
//  CoachingRequest; the prompt builder serializes them without any
//  SwiftData dependency.
//

import Foundation

/// Snapshot of one recorded weight entry, for prompt building.
public struct CoachStrengthWorkout: Codable, Equatable, Sendable {
    /// The day the workout was performed.
    public let date: Date
    /// Weight lifted in pounds.
    public let weightPounds: Double
    /// What the weight represents (e.g. "Max Weight", "Average Weight").
    public let recordingType: String
    /// Post-workout notes, or `nil` when empty.
    public let notes: String?

    public init(date: Date, weightPounds: Double, recordingType: String, notes: String? = nil) {
        self.date = date
        self.weightPounds = weightPounds
        self.recordingType = recordingType
        self.notes = notes
    }
}

/// Snapshot of one board exercise and its recorded history, for prompt
/// building. A board exercise has no date — it lives in a day-of-week lane
/// on the weekly strength template.
public struct CoachStrengthExercise: Codable, Equatable, Sendable {
    /// Display name, e.g. "Barbell Bench Press".
    public let name: String
    /// Primary muscle group raw value, e.g. "Chest". Kept as a string so a
    /// group introduced by a newer app version still serializes.
    public let muscleGroup: String
    /// Day-of-week lane (Sunday=0 ... Saturday=6).
    public let weekdayIndex: Int
    /// Whether the exercise is offloaded (out of the active weekly plan).
    public let isOffloaded: Bool
    /// User notes, or `nil` when empty.
    public let notes: String?
    /// Planned number of sets, or `nil` when no plan is set.
    public let plannedSets: Int?
    /// Planned reps per set, or `nil` when no plan is set.
    public let plannedReps: Int?
    /// Recorded weight entries, oldest first.
    public let workouts: [CoachStrengthWorkout]

    public init(
        name: String,
        muscleGroup: String,
        weekdayIndex: Int,
        isOffloaded: Bool,
        notes: String? = nil,
        plannedSets: Int? = nil,
        plannedReps: Int? = nil,
        workouts: [CoachStrengthWorkout] = []
    ) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.weekdayIndex = weekdayIndex
        self.isOffloaded = isOffloaded
        self.notes = notes
        self.plannedSets = plannedSets
        self.plannedReps = plannedReps
        self.workouts = workouts
    }
}
