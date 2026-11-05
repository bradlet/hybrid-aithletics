//
//  Expectation.swift
//  CoachEvalKit
//
//  The checks a scenario applies to a coach turn. Each is a label plus a pure
//  function from (transcript, scenario) to a verdict, built through the
//  static factories below so scenarios read like a spec:
//
//      expectations: [
//          .proposes(.recordWorkout),
//          .workoutOn(day: -1),
//          .workoutDistance(miles: 5),
//      ]
//

import Foundation
import AICoachCore

/// The outcome of one check on one sample.
public struct Verdict: Equatable, Sendable {
    /// Whether the check passed.
    public let passed: Bool
    /// What was observed — shown in reports on failure, so make it specific.
    public let detail: String

    /// A passing verdict.
    public static func pass(_ detail: String = "") -> Verdict { Verdict(passed: true, detail: detail) }
    /// A failing verdict.
    public static func fail(_ detail: String) -> Verdict { Verdict(passed: false, detail: detail) }

    /// Passes when `condition` holds; `detail` explains either way.
    public static func check(_ condition: Bool, _ detail: String) -> Verdict {
        Verdict(passed: condition, detail: detail)
    }
}

/// A named check on a coach turn.
///
/// A struct holding a closure, rather than an enum of every check kind, so a
/// new kind of check is one new static function — no switch to extend.
public struct Expectation: Sendable {
    /// Short description shown in reports, e.g. `proposes record_workout`.
    public let label: String
    /// The check itself. Pure: no I/O, no model.
    public let evaluate: @Sendable (TurnTranscript, EvalScenario) -> Verdict

    /// Creates an expectation from a label and a check.
    public init(
        _ label: String,
        evaluate: @escaping @Sendable (TurnTranscript, EvalScenario) -> Verdict
    ) {
        self.label = label
        self.evaluate = evaluate
    }
}

// MARK: - Turn shape

extension Expectation {

    /// The turn's (first) proposal calls `tool`.
    public static func proposes(_ tool: CoachTool) -> Expectation {
        Expectation("proposes \(tool.rawValue)") { transcript, _ in
            guard let proposal = transcript.proposal else {
                return .fail("no proposal; reply: \(transcript.trimmedReply.prefix(120))")
            }
            return .check(proposal.tool == tool, "got \(proposal.tool.rawValue)")
        }
    }

    /// The turn makes no proposal — the coach should talk, not act.
    ///
    /// The `chat` tool is a reply, not a proposal, so it passes this check.
    public static var noProposal: Expectation {
        Expectation("no proposal") { transcript, _ in
            guard let proposal = transcript.proposal else { return .pass() }
            return .fail("proposed \(ProposalSummary.describe(proposal))")
        }
    }

    /// No tool call was rejected by the decoder or the runtime's parser.
    public static var noRejections: Expectation {
        Expectation("no rejected tool calls") { transcript, _ in
            .check(transcript.rejections.isEmpty, transcript.rejections.joined(separator: "; "))
        }
    }
}

// MARK: - Reply text

extension Expectation {

    /// The athlete sees some text.
    public static var replyNotEmpty: Expectation {
        Expectation("reply not empty") { transcript, _ in
            .check(!transcript.trimmedReply.isEmpty, "\(transcript.wordCount) words")
        }
    }

    /// The reply asks the athlete something.
    public static var replyAsksQuestion: Expectation {
        Expectation("reply asks a question") { transcript, _ in
            .check(transcript.reply.contains("?"), "reply: \(transcript.trimmedReply.prefix(120))")
        }
    }

    /// The reply contains at least one of `words` (case-insensitive).
    public static func replyMentionsAny(_ words: [String]) -> Expectation {
        Expectation("reply mentions any of \(words.joined(separator: "/"))") { transcript, _ in
            let reply = transcript.reply.lowercased()
            let found = words.filter { reply.contains($0.lowercased()) }
            return .check(!found.isEmpty, found.isEmpty ? "none found" : "found \(found.joined(separator: ", "))")
        }
    }

    /// The reply contains none of `words` (case-insensitive). Useful for
    /// catching invented workout types or details absent from the snapshot.
    public static func replyOmits(_ words: [String]) -> Expectation {
        Expectation("reply omits \(words.joined(separator: "/"))") { transcript, _ in
            let reply = transcript.reply.lowercased()
            let found = words.filter { reply.contains($0.lowercased()) }
            return .check(found.isEmpty, found.isEmpty ? "" : "found \(found.joined(separator: ", "))")
        }
    }

    /// The reply is at most `limit` words.
    public static func maxWords(_ limit: Int) -> Expectation {
        Expectation("at most \(limit) words") { transcript, _ in
            .check(transcript.wordCount <= limit, "\(transcript.wordCount) words")
        }
    }
}

// MARK: - Proposal payloads

extension Expectation {

    /// Checks the payload of a proposal of one particular kind.
    ///
    /// Generic over the payload type `Payload`: `extract` pulls it out of a
    /// `CoachAction` (returning `nil` for any other kind), and `check` grades
    /// it. Fails when there is no proposal or it is a different kind.
    /// - Parameters:
    ///   - label: Report label.
    ///   - tool: The tool whose payload this reads, for the failure message.
    ///   - extract: Payload accessor, e.g. `\.workout`.
    ///   - check: Grades the payload.
    public static func payload<Payload>(
        _ label: String,
        of tool: CoachTool,
        _ extract: @escaping @Sendable (CoachAction) -> Payload?,
        check: @escaping @Sendable (Payload, EvalScenario) -> Verdict
    ) -> Expectation {
        Expectation(label) { transcript, scenario in
            guard let proposal = transcript.proposal else {
                return .fail("no \(tool.rawValue) proposal")
            }
            guard let payload = extract(proposal) else {
                return .fail("proposal was \(proposal.tool.rawValue)")
            }
            return check(payload, scenario)
        }
    }

    // MARK: record_workout

    /// The workout is dated `day` days from the scenario's today.
    public static func workoutOn(day offset: Int) -> Expectation {
        payload("workout dated today\(offsetLabel(offset))", of: .recordWorkout, \.workout) { workout, scenario in
            dateVerdict(workout.date, expectedOffset: offset, today: scenario.today)
        }
    }

    /// The workout has the given activity type.
    public static func workoutType(_ type: CoachExerciseType) -> Expectation {
        payload("workout type \(type.rawValue)", of: .recordWorkout, \.workout) { workout, _ in
            .check(workout.exerciseType == type, "got \(workout.exerciseType.rawValue)")
        }
    }

    /// The workout's distance is `miles` give or take `tolerance`.
    public static func workoutDistance(miles: Double, tolerance: Double = 0.05) -> Expectation {
        payload("workout distance \(miles) mi", of: .recordWorkout, \.workout) { workout, _ in
            guard let distance = workout.distanceMiles else { return .fail("no distance") }
            return .check(abs(distance - miles) <= tolerance, "got \(distance) mi")
        }
    }

    /// The workout's duration is `seconds` give or take `tolerance` seconds.
    public static func workoutDuration(seconds: Int, tolerance: Int = 30) -> Expectation {
        payload("workout duration \(seconds)s", of: .recordWorkout, \.workout) { workout, _ in
            guard let duration = workout.durationSeconds else { return .fail("no duration") }
            return .check(abs(duration - seconds) <= tolerance, "got \(duration)s")
        }
    }

    /// The workout's RPE (1–10) is exactly `value`, or absent when `nil`.
    public static func workoutExertion(_ value: Int?) -> Expectation {
        payload("workout RPE \(value.map(String.init) ?? "unset")", of: .recordWorkout, \.workout) { workout, _ in
            .check(workout.perceivedExertion == value, "got \(workout.perceivedExertion.map(String.init) ?? "unset")")
        }
    }

    /// The workout's feeling (1–5) is exactly `value`, or absent when `nil`.
    public static func workoutFeeling(_ value: Int?) -> Expectation {
        payload("workout feeling \(value.map(String.init) ?? "unset")", of: .recordWorkout, \.workout) { workout, _ in
            .check(workout.feeling == value, "got \(workout.feeling.map(String.init) ?? "unset")")
        }
    }

    // MARK: suggest_schedule_change

    /// The schedule change targets `day` days from the scenario's today.
    public static func scheduleChangeOn(day offset: Int) -> Expectation {
        payload("schedule change dated today\(offsetLabel(offset))", of: .suggestScheduleChange, \.scheduleChange) { change, scenario in
            dateVerdict(change.date, expectedOffset: offset, today: scenario.today)
        }
    }

    /// The schedule change is one of `kinds`.
    public static func scheduleChangeKind(_ kinds: ScheduleChangeKind...) -> Expectation {
        let names = kinds.map(\.rawValue).joined(separator: "/")
        return payload("schedule change kind \(names)", of: .suggestScheduleChange, \.scheduleChange) { change, _ in
            .check(kinds.contains(change.kind), "got \(change.kind.rawValue)")
        }
    }

    /// Free-form check on a schedule change.
    public static func scheduleChange(
        _ label: String,
        _ check: @escaping @Sendable (ScheduleChangeProposal) -> Verdict
    ) -> Expectation {
        payload(label, of: .suggestScheduleChange, \.scheduleChange) { change, _ in check(change) }
    }

    // MARK: plan_strength_day

    /// The strength day targets the named weekday lane, e.g. `"Tuesday"`.
    public static func strengthDayOn(_ weekday: String) -> Expectation {
        payload("strength day on \(weekday)", of: .planStrengthDay, \.strengthDay) { day, _ in
            .check(day.weekdayName == weekday, "got \(day.weekdayName)")
        }
    }

    /// The strength day carries between `range.lowerBound` and
    /// `range.upperBound` exercises.
    public static func strengthDayExerciseCount(_ range: ClosedRange<Int>) -> Expectation {
        payload("strength day has \(range.lowerBound)–\(range.upperBound) exercises", of: .planStrengthDay, \.strengthDay) { day, _ in
            .check(range.contains(day.exercises.count), "got \(day.exercises.count): \(day.exercises.map(\.name).joined(separator: ", "))")
        }
    }

    /// Free-form check on a strength day.
    public static func strengthDay(
        _ label: String,
        _ check: @escaping @Sendable (StrengthDayProposal) -> Verdict
    ) -> Expectation {
        payload(label, of: .planStrengthDay, \.strengthDay) { day, _ in check(day) }
    }

    // MARK: update_strength_exercise

    /// The update addresses an exercise in `weekday`'s lane whose name
    /// contains `nameFragment` (case-insensitive).
    public static func strengthUpdateTargets(_ weekday: String, nameContaining nameFragment: String) -> Expectation {
        payload("updates \"\(nameFragment)\" on \(weekday)", of: .updateStrengthExercise, \.strengthUpdate) { update, _ in
            let nameMatches = update.exerciseName.lowercased().contains(nameFragment.lowercased())
            return .check(
                update.weekdayName == weekday && nameMatches,
                "got \"\(update.exerciseName)\" on \(update.weekdayName)"
            )
        }
    }

    /// The update is of the given kind; for `.moveToDay`, pass the destination.
    public static func strengthUpdateKind(
        _ kind: StrengthExerciseChangeKind,
        to destination: String? = nil
    ) -> Expectation {
        let label = "strength update \(kind.rawValue)" + (destination.map { " to \($0)" } ?? "")
        return payload(label, of: .updateStrengthExercise, \.strengthUpdate) { update, _ in
            let observed = "got \(update.kind.rawValue)" + (update.newWeekdayName.map { " to \($0)" } ?? "")
            guard update.kind == kind else { return .fail(observed) }
            if let destination {
                return .check(update.newWeekdayName == destination, observed)
            }
            return .pass(observed)
        }
    }

    // MARK: Helpers

    /// `" -1"`, `" +2"`, or `""` for zero — for labels like "dated today -1".
    private static func offsetLabel(_ offset: Int) -> String {
        offset == 0 ? "" : (offset > 0 ? " +\(offset)" : " \(offset)")
    }

    /// Compares `date` against `today + expectedOffset` by calendar day.
    private static func dateVerdict(_ date: Date, expectedOffset: Int, today: Date) -> Verdict {
        let expected = EvalCalendar.day(expectedOffset, from: today)
        return .check(
            EvalCalendar.isSameDay(date, expected),
            "got \(EvalCalendar.label(date)), expected \(EvalCalendar.label(expected))"
        )
    }
}

// MARK: - Payload accessors

extension CoachAction {
    /// The payload of a `record_workout` proposal, else `nil`.
    public var workout: WorkoutProposal? {
        if case .recordWorkout(let proposal) = self { return proposal }
        return nil
    }

    /// The payload of a `suggest_schedule_change` proposal, else `nil`.
    public var scheduleChange: ScheduleChangeProposal? {
        if case .suggestScheduleChange(let proposal) = self { return proposal }
        return nil
    }

    /// The payload of a `plan_strength_day` proposal, else `nil`.
    public var strengthDay: StrengthDayProposal? {
        if case .planStrengthDay(let proposal) = self { return proposal }
        return nil
    }

    /// The payload of an `update_strength_exercise` proposal, else `nil`.
    public var strengthUpdate: StrengthExerciseUpdateProposal? {
        if case .updateStrengthExercise(let proposal) = self { return proposal }
        return nil
    }
}
