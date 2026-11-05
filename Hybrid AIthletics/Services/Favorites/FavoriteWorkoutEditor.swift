//
//  FavoriteWorkoutEditor.swift
//  Hybrid AIthletics
//
//  The pure value and mutation path behind favorite workouts, kept out of the
//  views so it can be unit-tested (same pattern as `UserLibraryEditor` and
//  `WorkoutEditor`). `FavoriteFormValues` is the one place that converts
//  between a stored favorite (miles, total seconds) and form state (display
//  units, h/m/s) — the record, schedule and favorite forms all go through it.
//

import Foundation
import SwiftData
import SwiftUI

// MARK: - Form Values

/// A favorite's fields in form units: distance in the athlete's display unit
/// and duration as total seconds split for the wheel pickers.
struct FavoriteFormValues: Equatable {
    /// Display name.
    var name: String = ""
    /// Exercise type.
    var type: ExerciseType = .run
    /// Duration in seconds; 0 means none.
    var durationSeconds: Int = 0
    /// Distance in the display unit (mi or km), or nil when none.
    var displayDistance: Double? = nil
    /// Whether it counts toward training mileage.
    var countsTowardMileage: Bool = true

    /// Whole hours of `durationSeconds`.
    var hours: Int { durationSeconds / 3600 }
    /// Remaining minutes of `durationSeconds` after whole hours.
    var minutes: Int { (durationSeconds % 3600) / 60 }
    /// Remaining seconds of `durationSeconds` after whole minutes.
    var seconds: Int { durationSeconds % 60 }

    /// Creates form values from explicit fields.
    /// - Parameters:
    ///   - name: Display name.
    ///   - type: Exercise type.
    ///   - durationSeconds: Duration in seconds.
    ///   - displayDistance: Distance in the display unit; nil or 0 means none.
    ///   - countsTowardMileage: Whether it counts toward training mileage.
    init(
        name: String = "",
        type: ExerciseType = .run,
        durationSeconds: Int = 0,
        displayDistance: Double? = nil,
        countsTowardMileage: Bool = true
    ) {
        self.name = name
        self.type = type
        self.durationSeconds = max(durationSeconds, 0)
        self.displayDistance = displayDistance.flatMap { $0 > 0 ? $0 : nil }
        self.countsTowardMileage = countsTowardMileage
    }

    /// Reads a stored favorite into form units. A zero distance becomes nil
    /// so the field shows its placeholder rather than a literal 0.0.
    /// - Parameters:
    ///   - favorite: The stored favorite.
    ///   - metric: Whether the form shows kilometres.
    init(_ favorite: FavoriteWorkout, metric: Bool) {
        self.init(
            name: favorite.name,
            type: favorite.type,
            durationSeconds: favorite.durationSeconds,
            displayDistance: favorite.distanceMiles > 0
                ? favorite.distanceMiles.toDisplayDistance(metric: metric)
                : nil,
            countsTowardMileage: favorite.countsTowardMileage
        )
    }

    /// Seeds a favorite from a recorded workout's form, preferring its planned
    /// targets and falling back to the recorded actuals for any target that is
    /// unset (a quick-added workout's plan mirrors its actuals anyway).
    /// - Parameters:
    ///   - name: Workout name.
    ///   - type: Exercise type.
    ///   - plannedDurationSeconds: Planned duration in seconds.
    ///   - plannedDisplayDistance: Planned distance in the display unit.
    ///   - actualDurationSeconds: Recorded duration in seconds.
    ///   - actualDisplayDistance: Recorded distance in the display unit.
    ///   - countsTowardMileage: Whether it counts toward training mileage.
    /// - Returns: The seeded form values.
    static func plannedFirst(
        name: String,
        type: ExerciseType,
        plannedDurationSeconds: Int,
        plannedDisplayDistance: Double?,
        actualDurationSeconds: Int,
        actualDisplayDistance: Double?,
        countsTowardMileage: Bool
    ) -> FavoriteFormValues {
        let planned = (plannedDisplayDistance ?? 0) > 0 ? plannedDisplayDistance : nil
        return FavoriteFormValues(
            name: name,
            type: type,
            durationSeconds: plannedDurationSeconds > 0 ? plannedDurationSeconds : actualDurationSeconds,
            displayDistance: planned ?? actualDisplayDistance,
            countsTowardMileage: countsTowardMileage
        )
    }

    /// Total seconds for a wheel-picker duration.
    /// - Parameters:
    ///   - hours: Whole hours.
    ///   - minutes: Minutes.
    ///   - seconds: Seconds.
    /// - Returns: The duration in seconds.
    static func durationSeconds(hours: Int, minutes: Int, seconds: Int) -> Int {
        hours * 3600 + minutes * 60 + seconds
    }

    /// The distance converted back to miles for storage; 0 when none.
    /// - Parameter metric: Whether `displayDistance` is in kilometres.
    /// - Returns: The distance in miles.
    func distanceMiles(metric: Bool) -> Double {
        let display = displayDistance ?? 0
        return metric ? display / 1.60934 : display
    }
}

// MARK: - Editor

/// Owns the favorite-workout mutation path so it can be unit-tested without a view.
enum FavoriteWorkoutEditor {
    /// Inserts a new favorite at the end of the manual ordering and saves.
    /// - Parameters:
    ///   - values: The form values; the name is trimmed.
    ///   - metric: Whether `values.displayDistance` is in kilometres.
    ///   - context: The context to insert into.
    /// - Returns: The new favorite, or nil when the trimmed name is empty.
    @discardableResult
    static func make(
        from values: FavoriteFormValues,
        metric: Bool,
        in context: ModelContext
    ) throws -> FavoriteWorkout? {
        let trimmedName = values.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return nil }
        let existing = try context.fetch(FetchDescriptor<FavoriteWorkout>())
        let nextOrder = (existing.map(\.sortOrder).max() ?? -1) + 1
        let favorite = FavoriteWorkout(
            name: trimmedName,
            type: values.type,
            distanceMiles: values.distanceMiles(metric: metric),
            durationSeconds: values.durationSeconds,
            countsTowardMileage: values.countsTowardMileage,
            sortOrder: nextOrder
        )
        context.insert(favorite)
        try context.save()
        return favorite
    }

    /// Overwrites a favorite's fields from form values. Leaves the favorite
    /// untouched when the trimmed name is empty.
    /// - Parameters:
    ///   - favorite: The favorite to update.
    ///   - values: The form values; the name is trimmed.
    ///   - metric: Whether `values.displayDistance` is in kilometres.
    /// - Returns: Whether the favorite was updated.
    @discardableResult
    static func update(_ favorite: FavoriteWorkout, with values: FavoriteFormValues, metric: Bool) -> Bool {
        let trimmedName = values.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return false }
        favorite.name = trimmedName
        favorite.type = values.type
        favorite.distanceMiles = values.distanceMiles(metric: metric)
        favorite.durationSeconds = values.durationSeconds
        favorite.countsTowardMileage = values.countsTowardMileage
        return true
    }

    /// Deletes a favorite and saves.
    /// - Parameters:
    ///   - favorite: The favorite to delete.
    ///   - context: The context to delete from.
    static func delete(_ favorite: FavoriteWorkout, in context: ModelContext) throws {
        context.delete(favorite)
        try context.save()
    }

    /// Applies a list reorder and renumbers every favorite's `sortOrder` to
    /// its new position (0…n-1), healing any gaps or ties along the way.
    /// - Parameters:
    ///   - favorites: The favorites in their current display order.
    ///   - source: Offsets being moved, as `List.onMove` reports them.
    ///   - destination: The destination offset, as `List.onMove` reports it.
    static func move(_ favorites: [FavoriteWorkout], fromOffsets source: IndexSet, toOffset destination: Int) {
        var reordered = favorites
        reordered.move(fromOffsets: source, toOffset: destination)
        for (index, favorite) in reordered.enumerated() {
            favorite.sortOrder = index
        }
    }
}
