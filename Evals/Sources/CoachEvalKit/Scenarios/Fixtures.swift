//
//  Fixtures.swift
//  CoachEvalKit
//
//  Training snapshots the scenarios share. Dates are offsets from
//  `EvalCalendar.today` (Wednesday 2026-10-14), so "yesterday" is Tuesday.
//

import Foundation
import AICoachCore

/// Reusable training snapshots.
public enum Fixtures {

    /// Shorthand for a day relative to the fixed eval date.
    private static func day(_ offset: Int) -> Date { EvalCalendar.day(offset) }

    /// A healthy week: moderate running load, a tempo run tomorrow, and a
    /// three-day strength board (Mon legs, Wed push, Fri pull) with Tuesday,
    /// Thursday, and the weekend lanes empty.
    public static let typicalWeek = CoachingRequest(
        recentWorkouts: [
            CoachWorkout(date: day(-6), type: .easyRun, distanceMiles: 4.0,
                         durationSeconds: 2160, feeling: 4, perceivedExertion: 4),
            CoachWorkout(date: day(-4), type: .intervalRun, distanceMiles: 5.0,
                         durationSeconds: 2520, feeling: 3, perceivedExertion: 7,
                         notes: "6x800m"),
            // Feeling left unrecorded — the prompt omits it, as the app does.
            CoachWorkout(date: day(-3), type: .easyRun, distanceMiles: 3.0,
                         durationSeconds: 1680, perceivedExertion: 3),
            CoachWorkout(date: day(-2), type: .longRun, distanceMiles: 9.0,
                         durationSeconds: 4860, feeling: 3, perceivedExertion: 6),
        ],
        upcomingExercises: [
            CoachExercise(scheduledDate: day(1), type: .tempoRun,
                          distanceMiles: 6.0, durationSeconds: 2880),
            CoachExercise(scheduledDate: day(3), type: .easyRun,
                          distanceMiles: 4.0, durationSeconds: 2160),
            CoachExercise(scheduledDate: day(4), type: .longRun,
                          distanceMiles: 10.0, durationSeconds: 5400),
        ],
        strengthExercises: [
            CoachStrengthExercise(name: "Back Squat", muscleGroup: "Quads", weekdayIndex: 1,
                                  isOffloaded: false, plannedSets: 4, plannedReps: 6),
            CoachStrengthExercise(name: "Romanian Deadlift", muscleGroup: "Hamstrings", weekdayIndex: 1,
                                  isOffloaded: false, plannedSets: 3, plannedReps: 8),
            CoachStrengthExercise(name: "Barbell Bench Press", muscleGroup: "Chest", weekdayIndex: 3,
                                  isOffloaded: false, plannedSets: 4, plannedReps: 6),
            CoachStrengthExercise(name: "Overhead Press", muscleGroup: "Shoulders", weekdayIndex: 3,
                                  isOffloaded: false, plannedSets: 3, plannedReps: 8),
            CoachStrengthExercise(name: "Pull-Up", muscleGroup: "Back", weekdayIndex: 5,
                                  isOffloaded: false, plannedSets: 4, plannedReps: 8),
            CoachStrengthExercise(name: "Barbell Row", muscleGroup: "Back", weekdayIndex: 5,
                                  isOffloaded: false, plannedSets: 3, plannedReps: 10),
        ],
        useMetricUnits: false
    )

    /// Clear overtraining: five hard sessions in a week, all feeling weak, with
    /// a demanding plan ahead. Ported from the old one-shot `high-rpe` case.
    public static let overtraining = CoachingRequest(
        recentWorkouts: [
            CoachWorkout(date: day(-6), type: .tempoRun, distanceMiles: 6.0,
                         durationSeconds: 2700, feeling: 2, perceivedExertion: 8,
                         notes: "felt sluggish"),
            CoachWorkout(date: day(-5), type: .easyRun, distanceMiles: 5.0,
                         durationSeconds: 2400, feeling: 2, perceivedExertion: 8,
                         notes: "legs heavy"),
            CoachWorkout(date: day(-4), type: .intervalRun, distanceMiles: 4.0,
                         durationSeconds: 2100, feeling: 1, perceivedExertion: 9,
                         notes: "struggled on last interval"),
            CoachWorkout(date: day(-2), type: .longRun, distanceMiles: 12.0,
                         durationSeconds: 5400, feeling: 1, perceivedExertion: 9,
                         notes: "had to walk last mile"),
            CoachWorkout(date: day(-1), type: .easyRun, distanceMiles: 4.0,
                         durationSeconds: 2100, perceivedExertion: 8),
        ],
        upcomingExercises: [
            CoachExercise(scheduledDate: day(1), type: .intervalRun,
                          distanceMiles: 5.0, durationSeconds: 2400),
            CoachExercise(scheduledDate: day(3), type: .tempoRun,
                          distanceMiles: 7.0, durationSeconds: 3000),
            CoachExercise(scheduledDate: day(5), type: .longRun,
                          distanceMiles: 14.0, durationSeconds: 6000),
        ],
        useMetricUnits: false
    )

    /// A brand-new athlete: nothing recorded, nothing planned.
    public static let empty = CoachingRequest(
        recentWorkouts: [],
        upcomingExercises: [],
        useMetricUnits: false
    )
}
