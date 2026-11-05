//
//  FavoriteWorkout.swift
//  Hybrid AIthletics
//
//  A saved aerobic workout preset ("favorite"). Picking one pre-fills the
//  record and schedule sheets with its identity and targets, so a session the
//  athlete repeats doesn't have to be re-entered field by field. A favorite is
//  a preset, never a workout: it holds no date or ratings and is not exported
//  to Google Sheets.
//

import Foundation
import SwiftData

@Model
final class FavoriteWorkout {
    /// Unique identifier.
    var id: UUID = UUID()
    /// Display name, e.g. "Easy 5 mi loop".
    var name: String = ""
    /// The exercise type the favorite pre-fills.
    var type: ExerciseType = ExerciseType.run
    /// Target distance in miles (always miles internally); 0 means no distance.
    var distanceMiles: Double = 0.0
    /// Target duration in seconds; 0 means no duration.
    var durationSeconds: Int = 0
    /// Whether workouts started from this favorite count toward training
    /// mileage (see `Exercise.countsTowardMileage`).
    var countsTowardMileage: Bool = true
    /// Position in the athlete's manual ordering, ascending.
    var sortOrder: Int = 0
    /// Creation timestamp, a tie-breaker for equal `sortOrder`s (e.g. two
    /// devices appending at once before CloudKit syncs).
    var createdAt: Date = Date()

    /// Creates a favorite workout. The id and creation timestamp are
    /// generated automatically.
    /// - Parameters:
    ///   - name: Display name.
    ///   - type: Exercise type.
    ///   - distanceMiles: Target distance in miles, 0 for none.
    ///   - durationSeconds: Target duration in seconds, 0 for none.
    ///   - countsTowardMileage: Whether it counts toward training mileage.
    ///   - sortOrder: Position in the manual ordering.
    init(
        name: String,
        type: ExerciseType = .run,
        distanceMiles: Double = 0,
        durationSeconds: Int = 0,
        countsTowardMileage: Bool = true,
        sortOrder: Int = 0
    ) {
        self.id = UUID()
        self.name = name
        self.type = type
        self.distanceMiles = distanceMiles
        self.durationSeconds = durationSeconds
        self.countsTowardMileage = countsTowardMileage
        self.sortOrder = sortOrder
        self.createdAt = Date()
    }
}

// MARK: - Display

extension FavoriteWorkout {
    /// One-line target summary for rows and menus, e.g. "5.0 mi · 45:00".
    /// Unset targets are omitted; empty when the favorite has neither.
    /// - Parameter metric: Whether to show kilometres.
    /// - Returns: The summary string.
    func targetSummary(metric: Bool) -> String {
        var parts: [String] = []
        if distanceMiles > 0 { parts.append(distanceMiles.formattedDistance(metric: metric)) }
        if durationSeconds > 0 { parts.append(durationSeconds.formattedDuration) }
        return parts.joined(separator: " · ")
    }
}
