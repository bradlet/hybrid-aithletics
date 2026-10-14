//
//  CoachTypeConversions.swift
//  Hybrid AIthletics
//
//  Extensions to convert the app's SwiftData `Exercise` model (and its nested
//  `Workout` value) into AICoachCore's plain types for prompt building.
//

import Foundation
import AICoachCore

extension CoachExerciseType {

    /// Creates a coaching exercise type from the app's UI-aware `ExerciseType`.
    init(from appType: ExerciseType) {
        // Raw values are identical between the two enums by design.
        self = CoachExerciseType(rawValue: appType.rawValue)!
    }
}

extension ExerciseType {

    /// Creates the app's UI-aware exercise type from a coaching type.
    ///
    /// The reverse of `CoachExerciseType(from:)`. Raw values are identical by
    /// design, so an unknown value means the two enums have drifted apart —
    /// fall back to `.other` rather than trapping on data that arrived from a
    /// language model.
    init(from coachType: CoachExerciseType) {
        self = ExerciseType(rawValue: coachType.rawValue) ?? .other
    }
}

extension CoachWorkout {

    /// Creates a coaching workout from a completed `Exercise` (one whose
    /// `workout` is non-nil). Date and type come from the exercise; the
    /// metrics and ratings come from the recorded `workout`. Falls back to the
    /// planned metrics if `workout` is unexpectedly nil.
    init(from exercise: Exercise) {
        self.init(
            date: exercise.date,
            type: CoachExerciseType(from: exercise.type),
            distanceMiles: exercise.workout?.distanceMiles ?? exercise.distanceMiles,
            durationSeconds: exercise.workout?.durationSeconds ?? exercise.durationSeconds,
            // `workout?.feeling` is Int?? — flatten so an absent workout and
            // an unrated one both arrive as nil.
            feeling: exercise.workout?.feeling ?? nil,
            perceivedExertion: exercise.workout?.perceivedExertion ?? nil,
            notes: exercise.workout?.notes ?? ""
        )
    }
}

extension CoachExercise {

    /// Creates a coaching exercise from the app's SwiftData `Exercise` model,
    /// reading its planned (target) metrics.
    init(from exercise: Exercise) {
        self.init(
            scheduledDate: exercise.date,
            type: CoachExerciseType(from: exercise.type),
            distanceMiles: exercise.distanceMiles,
            durationSeconds: exercise.durationSeconds
        )
    }
}
