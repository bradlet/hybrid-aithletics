//
//  Workout.swift
//  Hybrid AIthletics
//
//  Recorded-instance data for an `Exercise`. This is a plain Codable value
//  type (NOT a SwiftData @Model) stored inline on `Exercise.workout`, so an
//  exercise and its recorded performance are a single entity. The activity's
//  date lives on `Exercise.date`; this type carries only the data that exists
//  once the activity has actually been performed.
//

import Foundation

/// Recorded performance for an `Exercise`. Persisted as a Codable composite
/// attribute on `Exercise.workout` (CloudKit-compatible, no separate table).
struct Workout: Codable, Hashable, Sendable {
    /// Actual duration in seconds.
    var durationSeconds: Int = 0
    /// Actual distance in miles (internal storage unit).
    var distanceMiles: Double = 0.0
    /// Post-workout notes about the completed session.
    var notes: String = ""
    /// How the athlete felt, 1 (Very Weak) … 5 (Very Strong). `nil` means the
    /// user did not record a feeling. Feeds the AI Coach.
    var feeling: Int? = nil
    /// Rate of Perceived Exertion, 1 (Very Light) … 10 (Maximum).
    /// `nil` means the user did not record it. Feeds the AI Coach.
    ///
    /// Independent of `feeling`: a high exertion the athlete felt strong
    /// through is a good session, whereas the same exertion felt weak is an
    /// overreaching signal.
    var perceivedExertion: Int? = nil
    /// Provenance of this recorded workout. Stores the raw value of a
    /// `WorkoutSource` (e.g. "Manual", "CSV", "Apple Exercise App"). Stored
    /// as String for forward-extensibility.
    var source: String = WorkoutSource.manual.rawValue
    /// Stable identifier from the external source that produced this record
    /// (e.g. `HKWorkout.uuid.uuidString`). Used for deduplication on re-import.
    /// `nil` for manual entries.
    var externalID: String? = nil

    /// Creates a recorded workout.
    /// - Parameters:
    ///   - durationSeconds: Actual duration in seconds.
    ///   - distanceMiles: Actual distance in miles.
    ///   - notes: Optional post-workout notes.
    ///   - feeling: Subjective 1–5 feeling. `nil` means not recorded.
    ///   - perceivedExertion: Subjective 1–10 RPE. `nil` means not recorded.
    ///   - source: Provenance string. Defaults to `WorkoutSource.manual`.
    ///   - externalID: External source identifier for dedup. Defaults to `nil`.
    init(
        durationSeconds: Int = 0,
        distanceMiles: Double = 0.0,
        notes: String = "",
        feeling: Int? = nil,
        perceivedExertion: Int? = nil,
        source: String = WorkoutSource.manual.rawValue,
        externalID: String? = nil
    ) {
        self.durationSeconds = durationSeconds
        self.distanceMiles = distanceMiles
        self.notes = notes
        self.feeling = feeling
        self.perceivedExertion = perceivedExertion
        self.source = source
        self.externalID = externalID
    }

    /// Creates a draft workout pre-filled with the actuals from a planned
    /// exercise's targets. The user can edit all fields before saving. Starts
    /// unrated (both ratings `nil`) with empty notes and a manual source.
    /// - Parameter exercise: The exercise to copy target metrics from.
    init(draftFrom exercise: Exercise) {
        self.init(
            durationSeconds: exercise.durationSeconds,
            distanceMiles: exercise.distanceMiles,
            notes: "",
            feeling: nil,
            perceivedExertion: nil,
            source: WorkoutSource.manual.rawValue,
            externalID: nil
        )
    }
}
