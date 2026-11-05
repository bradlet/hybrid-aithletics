//
//  ProposalSummary.swift
//  CoachEvalKit
//
//  One-line, human-readable renderings of coach proposals for reports and
//  the interactive chat.
//

import Foundation
import AICoachCore

/// Formats a `CoachAction` as a single readable line.
public enum ProposalSummary {

    /// Describes an action, e.g.
    /// `record_workout 2026-10-13 Tue · Easy Run · 5.0 mi · 42:00 · feeling 4`.
    public static func describe(_ action: CoachAction) -> String {
        let tool = action.tool.rawValue
        switch action {
        case .reply(let text):
            return "\(tool): \(text)"
        case .recordWorkout(let w):
            let parts: [String?] = [
                EvalCalendar.label(w.date),
                w.exerciseType.rawValue,
                w.distanceMiles.map { String(format: "%.1f mi", $0) },
                w.durationSeconds.map(clock),
                w.perceivedExertion.map { "RPE \($0)" },
                w.feeling.map { "feeling \($0)" },
                w.notes.map { "notes \"\($0)\"" },
            ]
            return "\(tool) " + parts.compactMap { $0 }.joined(separator: " · ")
        case .suggestScheduleChange(let c):
            let parts: [String?] = [
                EvalCalendar.label(c.date),
                c.kind.rawValue,
                c.exerciseType?.rawValue,
                c.distanceMiles.map { String(format: "%.1f mi", $0) },
                c.durationSeconds.map(clock),
                "why: \(c.rationale)",
            ]
            return "\(tool) " + parts.compactMap { $0 }.joined(separator: " · ")
        case .planStrengthDay(let d):
            let lifts = d.exercises.map { e in
                let plan = (e.plannedSets).flatMap { s in e.plannedReps.map { "\(s)x\($0)" } }
                return "\(e.name) (\(e.muscleGroup.rawValue))" + (plan.map { " \($0)" } ?? "")
            }
            return "\(tool) \(d.weekdayName): " + lifts.joined(separator: "; ")
        case .updateStrengthExercise(let u):
            let destination = u.newWeekdayName.map { " → \($0)" } ?? ""
            return "\(tool) \(u.kind.rawValue) \"\(u.exerciseName)\" on \(u.weekdayName)\(destination)"
        }
    }

    /// Formats seconds as `m:ss`, or `h:mm:ss` from an hour up.
    static func clock(_ seconds: Int) -> String {
        let h = seconds / 3600, m = (seconds % 3600) / 60, s = seconds % 60
        return h > 0
            ? String(format: "%d:%02d:%02d", h, m, s)
            : String(format: "%d:%02d", m, s)
    }
}
