//
//  StrengthScenarios.swift
//  CoachEvalKit
//
//  The weekly strength board: `plan_strength_day` adds, and
//  `update_strength_exercise` changes what is already there.
//

import Foundation
import AICoachCore

extension ScenarioLibrary {

    /// The coach chooses the lifts — the athlete names only the day and focus.
    /// Exercises a nested-looking argument the model must send as the flat
    /// line-format string.
    public static let strengthPlanDay = EvalScenario(
        id: "strength-plan-day",
        title: "Program a leg day",
        summary: "Tuesday's lane is empty. Expect one plan_strength_day for " +
            "Tuesday with 1–8 exercises, the coach picking them.",
        tags: ["strength", "plan"],
        snapshot: Fixtures.typicalWeek,
        athleteMessage: "Plan a leg day for me on Tuesday.",
        expectations: [
            .proposes(.planStrengthDay),
            .strengthDayOn("Tuesday"),
            .strengthDayExerciseCount(1...StrengthDayProposal.maxExercises),
            .strengthDay("targets legs") { day in
                let legGroups: Set<CoachMuscleGroup> = [.quads, .hamstrings, .glutes, .calves]
                let legs = day.exercises.filter { legGroups.contains($0.muscleGroup) }.count
                return .check(legs * 2 >= day.exercises.count, "\(legs)/\(day.exercises.count) leg exercises")
            },
            .noRejections,
        ]
    )

    /// One exercise is also a `plan_strength_day` call — it appends.
    public static let strengthAddOne = EvalScenario(
        id: "strength-add-one",
        title: "Add a single exercise",
        summary: "Expect plan_strength_day on Friday carrying exactly one " +
            "exercise named like \"face pull\", 3 x 15.",
        tags: ["strength", "plan"],
        snapshot: Fixtures.typicalWeek,
        athleteMessage: "Add face pulls to Friday, 3 sets of 15.",
        expectations: [
            .proposes(.planStrengthDay),
            .strengthDayOn("Friday"),
            .strengthDayExerciseCount(1...1),
            .strengthDay("face pulls 3x15") { day in
                guard let lift = day.exercises.first else { return .fail("no exercises") }
                let named = lift.name.lowercased().contains("face pull")
                let planned = lift.plannedSets == 3 && lift.plannedReps == 15
                return .check(named && planned, "\(lift.name) \(lift.plannedSets.map(String.init) ?? "-")x\(lift.plannedReps.map(String.init) ?? "-")")
            },
            .noRejections,
        ]
    )

    /// Moving is an update, addressed by the exercise's current lane and name.
    public static let strengthMove = EvalScenario(
        id: "strength-move",
        title: "Move an exercise to another day",
        summary: "Expect update_strength_exercise move_to_day for the Monday " +
            "Romanian Deadlift, destination Thursday.",
        tags: ["strength", "update"],
        snapshot: Fixtures.typicalWeek,
        athleteMessage: "Move my Romanian deadlifts from Monday to Thursday.",
        expectations: [
            .proposes(.updateStrengthExercise),
            .strengthUpdateTargets("Monday", nameContaining: "romanian"),
            .strengthUpdateKind(.moveToDay, to: "Thursday"),
            .noRejections,
        ]
    )

    /// "For now" means offload (keep it, out of the active plan), not remove.
    public static let strengthOffload = EvalScenario(
        id: "strength-offload",
        title: "Offload, don't delete",
        summary: "A temporary injury. Expect update_strength_exercise offload of " +
            "Wednesday's bench press, not remove.",
        tags: ["strength", "update"],
        snapshot: Fixtures.typicalWeek,
        athleteMessage: "I tweaked my shoulder. Take bench press off Wednesday's plan for now.",
        expectations: [
            .proposes(.updateStrengthExercise),
            .strengthUpdateTargets("Wednesday", nameContaining: "bench"),
            .strengthUpdateKind(.offload),
            .noRejections,
        ]
    )
}
