//
//  TodayTraining.swift
//  Hybrid AIthletics
//
//  Pure selection of what the Home tab shows for a given day. Kept out of the
//  view so the day-matching and ordering rules are unit-testable, the same
//  pattern as `CalendarDayDot` and `StrengthBoardPlanner`.
//

import Foundation

/// Picks out one day's training from the full exercise sets.
enum TodayTraining {

    /// The day's aerobic activity, with unrecorded sessions first.
    ///
    /// Planned-but-unrecorded sessions lead because they are the ones the
    /// athlete can still act on; recorded ones are a record of what happened.
    /// Within each group, ordering is by time of day.
    ///
    /// - Parameters:
    ///   - all: Every exercise.
    ///   - day: Any timestamp inside the day of interest.
    /// - Returns: The day's exercises, unrecorded first then recorded.
    static func aerobic(_ all: [Exercise], on day: Date) -> [Exercise] {
        all
            .filter { Calendar.current.isDate($0.date, inSameDayAs: day) }
            // `isCompleted` reads the backing Data? directly — never decode
            // `workout` just to order a list.
            .sorted { lhs, rhs in
                if lhs.isCompleted != rhs.isCompleted {
                    return !lhs.isCompleted
                }
                return lhs.date < rhs.date
            }
    }

    /// The day's active strength lane, in board order.
    ///
    /// Offloaded exercises are excluded: they are deliberately out of the
    /// week's plan, so they are not today's work.
    ///
    /// - Parameters:
    ///   - all: Every strength exercise.
    ///   - day: Any timestamp inside the day of interest.
    /// - Returns: The day's active lane, ordered by `sortOrder`.
    static func strength(_ all: [StrengthExercise], on day: Date) -> [StrengthExercise] {
        StrengthBoardPlanner.lane(all, day: day.weekdayIndex, offloaded: false)
    }

    /// Whether the day has nothing scheduled or recorded at all.
    static func isEmpty(
        aerobic aerobicExercises: [Exercise],
        strength strengthExercises: [StrengthExercise]
    ) -> Bool {
        aerobicExercises.isEmpty && strengthExercises.isEmpty
    }
}
