//
//  ScheduleScenarios.swift
//  CoachEvalKit
//
//  `suggest_schedule_change` and plain coaching advice about the running plan.
//

import Foundation
import AICoachCore

extension ScenarioLibrary {

    /// A relative-date edit to a session that exists in the snapshot.
    public static let scheduleShortenTomorrow = EvalScenario(
        id: "schedule-shorten-tomorrow",
        title: "Shorten tomorrow's tempo run",
        summary: "Tomorrow holds a 6 mi tempo run. Expect a schedule change " +
            "dated tomorrow that shortens it (distance under 6 mi or a shorter duration).",
        tags: ["schedule", "dates"],
        snapshot: Fixtures.typicalWeek,
        athleteMessage: "My legs are toast. Can you make tomorrow's tempo run shorter?",
        expectations: [
            .proposes(.suggestScheduleChange),
            .scheduleChangeOn(day: 1),
            .scheduleChangeKind(.adjustDistance, .adjustDuration),
            .scheduleChange("new target is shorter") { change in
                if let miles = change.distanceMiles {
                    return .check(miles < 6, "distance \(miles) mi")
                }
                if let seconds = change.durationSeconds {
                    return .check(seconds < 2880, "duration \(seconds)s")
                }
                return .fail("no new distance or duration")
            },
            .noRejections,
        ]
    )

    /// Advice grounded in the snapshot: back off, and don't invent activities
    /// the athlete never did.
    public static let overtrainingAdvice = EvalScenario(
        id: "overtraining-advice",
        title: "Spot overtraining",
        summary: "Five hard, weak-feeling sessions and a demanding week ahead. " +
            "Expect advice to back off, mentioning no activity types absent from the data.",
        tags: ["chat", "advice"],
        snapshot: Fixtures.overtraining,
        athleteMessage: "How is my training going?",
        expectations: [
            .replyNotEmpty,
            .replyMentionsAny(["rest", "recover", "easy", "reduce", "back off", "fatigue", "lighter"]),
            .replyOmits(["swim", "bike", "cycling", "hike", "elliptical"]),
            .maxWords(250),
            .noRejections,
        ]
    )
}
