//
//  UITestFixtures.swift
//  Hybrid AIthletics
//
//  Deterministic exercise fixtures used by UI test targets.
//  Activated only when the app is launched with `-uiTestSeed`.
//

import Foundation
import SwiftData

/// Seeds a deterministic set of exercises into the shared model container so
/// UI tests can exercise pagination, calendar navigation, detail-sheet, and
/// aerobic training flows against a known data set.
enum UITestFixtures {

    /// Number of recorded fixture exercises. 25 across 10-per-page → 3 pages,
    /// enough to exercise pagination boundaries and last-page-clamp on delete.
    static let workoutCount = 25

    /// Number of strength exercises seeded into today's lane. Two is enough
    /// for the Home tab's "which lift?" picker to appear.
    static let todayStrengthCount = 2

    /// Clears any existing exercises in the context and inserts fresh
    /// fixtures. The most recent recorded exercise is "Test Workout 1" (today)
    /// and the oldest is "Test Workout 25" (24 days ago); two additional
    /// planned-only exercises (no `workout`) seed the training calendar, and
    /// the strength board gets today's lane plus one other day.
    static func seed(into container: ModelContainer) {
        let context = container.mainContext

        // Wipe existing data so each UI test launch starts clean. This
        // is safe because seeding only runs under `-uiTestSeed`, which also
        // forces an in-memory preview container.
        if let existing = try? context.fetch(FetchDescriptor<Exercise>()) {
            for exercise in existing {
                context.delete(exercise)
            }
        }
        if let existing = try? context.fetch(FetchDescriptor<StrengthExercise>()) {
            for exercise in existing {
                context.delete(exercise)
            }
        }

        let calendar = Calendar.current
        let baseDate = Date()

        // Seed recorded exercises (one per day backward from today). Each
        // carries a `workout` so it appears in the History tab. Two fixtures
        // record a distance different from plan so the training tab's
        // completed/planned split renders in the above- and below-plan states.
        for index in 0..<workoutCount {
            let number = index + 1
            guard let day = calendar.date(byAdding: .day, value: -index, to: baseDate) else { continue }
            let duration = 1800 + (index * 60)   // 30m, 31m, 32m, ...
            let miles = 3.0 + Double(index) * 0.1
            // index 1 → "Test Workout 2" (yesterday): above plan (gold).
            // index 2 → "Test Workout 3" (two days ago): below plan (yellow).
            let workoutMiles: Double = switch index {
            case 1: miles + 1.0
            case 2: miles - 1.0
            default: miles
            }
            // Every 4th workout is opted out of training progress so the
            // History list's dimmed "Not training" row and the calendar's
            // hollow dot are both exercised under UI test. Index 3 is
            // "Test Workout 4".
            let countsTowardMileage = index % 4 != 3
            let exercise = Exercise(
                name: "Test Workout \(number)",
                type: countsTowardMileage ? .run : .walk,
                durationSeconds: duration,
                distanceMiles: miles,
                notes: "Seeded fixture \(number)",
                date: day,
                countsTowardMileage: countsTowardMileage,
                workout: Workout(
                    durationSeconds: duration,
                    distanceMiles: workoutMiles,
                    notes: "Seeded fixture \(number)",
                    // Every 5th workout is left unrated so the History
                    // chart's null-gap rendering and the dials' "Not set"
                    // state are both exercised under UI test.
                    feeling: index % 5 == 4 ? nil : 1 + (index % 5),
                    perceivedExertion: index % 5 == 4 ? nil : 1 + (index % 10)
                )
            )
            context.insert(exercise)
        }

        // Seed planned-only exercises for aerobic training UI tests.
        // A weekly series created through the production bulk path (4 rows).
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: baseDate) ?? baseDate
        let seriesSpec = ExerciseSeriesSpec(
            name: "Test Series Run",
            type: .run,
            startDate: tomorrow,
            cadence: .weekly,
            endDate: calendar.date(byAdding: .weekOfYear, value: 3, to: tomorrow) ?? tomorrow,
            baseDistanceMiles: 3.0,
            baseDurationSeconds: 1800
        )
        ExercisePlanner.createSeries(seriesSpec, in: context)

        // A concrete exercise tomorrow
        let concreteExercise = Exercise(
            name: "Test Concrete Run",
            type: .longRun,
            durationSeconds: 3600,
            distanceMiles: 6.0,
            date: tomorrow
        )
        context.insert(concreteExercise)

        seedStrength(into: context)

        try? context.save()
    }

    /// Seeds the strength board: `todayStrengthCount` exercises in today's
    /// lane, one offloaded (so Home's exclusion of offloaded work is
    /// exercised), and one on another day.
    private static func seedStrength(into context: ModelContext) {
        let today = Date().weekdayIndex
        let otherDay = (today + 1) % 7

        for index in 0..<todayStrengthCount {
            let exercise = StrengthExercise(
                name: "Test Lift \(index + 1)",
                muscleGroup: index == 0 ? .chest : .back,
                weekdayIndex: today,
                sortOrder: index,
                plannedSets: 3,
                plannedReps: 8 + index
            )
            context.insert(exercise)
        }

        context.insert(StrengthExercise(
            name: "Test Offloaded Lift",
            muscleGroup: .quads,
            weekdayIndex: today,
            isOffloaded: true,
            sortOrder: 0
        ))

        context.insert(StrengthExercise(
            name: "Test Other Day Lift",
            muscleGroup: .shoulders,
            weekdayIndex: otherDay,
            sortOrder: 0
        ))
    }
}
