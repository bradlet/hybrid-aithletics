//
//  RecordScenarios.swift
//  CoachEvalKit
//
//  `record_workout`: the coach turns a described workout into a proposal the
//  athlete confirms — but only once it actually knows what to record.
//

import Foundation
import AICoachCore

extension ScenarioLibrary {

    /// Everything needed is in one message; "yesterday" must resolve against
    /// the date in the system turn, not an example date.
    public static let recordYesterday = EvalScenario(
        id: "record-yesterday",
        title: "Record a fully described workout",
        summary: "Date, type, distance, and duration are all given. Expect one " +
            "record_workout proposal dated yesterday with the stated values.",
        tags: ["record", "dates"],
        snapshot: Fixtures.typicalWeek,
        athleteMessage: "I ran an easy 5 miles yesterday in 42 minutes.",
        expectations: [
            .proposes(.recordWorkout),
            .workoutOn(day: -1),
            .workoutType(.easyRun),
            .workoutDistance(miles: 5),
            .workoutDuration(seconds: 42 * 60),
            .noRejections,
        ]
    )

    /// The request supplies none of date, type, or size: the coach must ask,
    /// not guess. Encodes the "a tool call is the last step" invariant.
    public static let recordAskFirst = EvalScenario(
        id: "record-ask-first",
        title: "Ask before recording",
        summary: "\"Can you record a workout for me?\" gives nothing to record. " +
            "Expect a question back and no proposal.",
        tags: ["record", "invariant"],
        snapshot: Fixtures.typicalWeek,
        athleteMessage: "Can you record a workout for me?",
        expectations: [
            .noProposal,
            .replyAsksQuestion,
            .noRejections,
        ]
    )

    /// The follow-up to `recordAskFirst`: the details arrive on the second turn.
    public static let recordAfterDetails = EvalScenario(
        id: "record-after-details",
        title: "Record once the details arrive",
        summary: "Second turn of the ask-first exchange. Expect a bike workout " +
            "today of 45 minutes, feeling Strong (4).",
        tags: ["record", "multi-turn"],
        snapshot: Fixtures.typicalWeek,
        history: [
            CoachMessage(role: .user, text: "Can you record a workout for me?"),
            CoachMessage(role: .coach, text: "Sure! What did you do, which day was it, and how far or how long did you go?"),
        ],
        athleteMessage: "A bike ride this morning, 45 minutes. Felt strong.",
        expectations: [
            .proposes(.recordWorkout),
            .workoutOn(day: 0),
            .workoutType(.bike),
            .workoutDuration(seconds: 45 * 60),
            .workoutFeeling(4),
            .noRejections,
        ]
    )

    /// Feeling and RPE are independent; one must never be derived from the
    /// other. A hard session the athlete felt strong in is the case that
    /// catches an inversion.
    ///
    /// An interval session, because the snapshot plans no intervals: naming a
    /// planned session (tomorrow's tempo run) baits the model into copying the
    /// plan's date and targets, which is a different failure from this one.
    public static let recordSeparateRatings = EvalScenario(
        id: "record-separate-ratings",
        title: "Keep feeling and RPE independent",
        summary: "RPE 8 but felt strong: expect perceivedExertion 8 and feeling 4 " +
            "(\"strong\"), neither inferred from the other. 10k is 6.2 miles.",
        tags: ["record", "invariant"],
        snapshot: Fixtures.typicalWeek,
        athleteMessage: "Log today's interval session: 10k in 48 minutes. RPE 8, but I felt strong.",
        expectations: [
            .proposes(.recordWorkout),
            .workoutOn(day: 0),
            .workoutType(.intervalRun),
            .workoutDistance(miles: 6.21, tolerance: 0.1),
            .workoutDuration(seconds: 48 * 60),
            .workoutExertion(8),
            .workoutFeeling(4),
        ]
    )
}
