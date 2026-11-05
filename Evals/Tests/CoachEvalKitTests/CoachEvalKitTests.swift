//
//  CoachEvalKitTests.swift
//  CoachEvalKitTests
//
//  Tests for everything in the eval suite except the model: transcript
//  folding, every expectation kind, the runner, reports, and the scenario
//  library. Runs in milliseconds with `swift test`; no weights, no Metal.
//

import Foundation
import Testing
import AICoachCore
@testable import CoachEvalKit

/// Swift Testing declares its own `Expectation`; in this file the name means ours.
private typealias Expectation = CoachEvalKit.Expectation

// MARK: - Helpers

/// A minimal scenario for grading tests.
private func scenario(
    _ expectations: [Expectation],
    today: Date = EvalCalendar.today
) -> EvalScenario {
    EvalScenario(
        id: "test", title: "Test", summary: "", today: today,
        snapshot: nil, athleteMessage: "hi", expectations: expectations
    )
}

/// Grades `events` against one expectation and returns the verdict.
private func verdict(_ expectation: Expectation, _ events: [CoachEvent]) -> Verdict {
    expectation.evaluate(TurnTranscript.folding(events), scenario([expectation]))
}

private let yesterdayRun = WorkoutProposal(
    date: EvalCalendar.day(-1), exerciseType: .easyRun,
    distanceMiles: 5, durationSeconds: 2520, perceivedExertion: 4, feeling: 4
)

// MARK: - Eval Calendar Tests

struct EvalCalendarTests {

    @Test func todayIsAFixedWednesday() {
        let components = Calendar.current.dateComponents([.year, .month, .day, .weekday], from: EvalCalendar.today)
        #expect(components.year == 2026 && components.month == 10 && components.day == 14)
        #expect(components.weekday == 4) // Wednesday
    }

    @Test func dayOffsetsMoveByCalendarDays() {
        #expect(EvalCalendar.label(EvalCalendar.day(-1)) == "2026-10-13 Tue")
        #expect(EvalCalendar.label(EvalCalendar.day(2)) == "2026-10-16 Fri")
    }

    @Test func sameDayIgnoresTimeOfDay() {
        let midnight = Calendar.current.startOfDay(for: EvalCalendar.today)
        #expect(EvalCalendar.isSameDay(midnight, EvalCalendar.today))
        #expect(!EvalCalendar.isSameDay(midnight, EvalCalendar.day(1)))
    }
}

// MARK: - Turn Transcript Tests

struct TurnTranscriptTests {

    @Test func textChunksAndChatRepliesBothBecomeReplyText() {
        let transcript = TurnTranscript.folding([
            .textChunk("Nice "), .action(.reply("work.")),
        ])
        #expect(transcript.reply == "Nice work.")
        #expect(transcript.proposal == nil)
    }

    @Test func firstProposalWinsAndLaterOnesAreCounted() {
        // Mirrors CoachChatStore: a small model repeats calls; the card
        // must not rewrite itself.
        let second = WorkoutProposal(date: EvalCalendar.today, exerciseType: .walk, durationSeconds: 600)
        let transcript = TurnTranscript.folding([
            .action(.recordWorkout(yesterdayRun)),
            .action(.recordWorkout(second)),
        ])
        #expect(transcript.proposal == .recordWorkout(yesterdayRun))
        #expect(transcript.ignoredProposals == 1)
    }

    @Test func rejectionsAreKept() {
        let transcript = TurnTranscript.folding([.rejectedToolCall(reason: "missing date")])
        #expect(transcript.rejections == ["missing date"])
        #expect(transcript.events.count == 1)
    }

    @Test func collectingDrainsAStream() async throws {
        let stream = AsyncThrowingStream<CoachEvent, Error> { continuation in
            continuation.yield(.textChunk("a"))
            continuation.yield(.textChunk("b"))
            continuation.finish()
        }
        let transcript = try await TurnTranscript.collecting(stream)
        #expect(transcript.reply == "ab")
    }

    @Test func wordCountAndTrimming() {
        let transcript = TurnTranscript.folding([.textChunk("  one two\nthree  ")])
        #expect(transcript.wordCount == 3)
        #expect(transcript.trimmedReply == "one two\nthree")
    }
}

// MARK: - Scenario Tests

struct EvalScenarioTests {

    @Test func chatRequestAppendsTheAthleteMessageAfterHistory() {
        let s = EvalScenario(
            id: "s", title: "S", summary: "", snapshot: Fixtures.empty,
            history: [
                CoachMessage(role: .user, text: "first"),
                CoachMessage(role: .coach, text: "reply"),
            ],
            athleteMessage: "second", expectations: []
        )
        let request = s.chatRequest()
        #expect(request.messages.map(\.text) == ["first", "reply", "second"])
        #expect(request.messages.last?.role == .user)
    }

    @Test func firstRequestCarriesTheSnapshot() {
        let request = ScenarioLibrary.recordYesterday.chatRequest()
        #expect(request.context != nil)
        let turns = AICoachPromptBuilder.buildChatTurns(for: request, today: EvalCalendar.today)
        #expect(turns[1].text.contains("Recent training"))
    }

    @Test func laterRequestsCarryNoSnapshotJustLikeTheApp() {
        // CoachChatStore sends context only on the first request and stores
        // plain athlete text, so turn two's prompt has no training data.
        let request = ScenarioLibrary.recordAfterDetails.chatRequest()
        #expect(request.context == nil)
        let turns = AICoachPromptBuilder.buildChatTurns(for: request, today: EvalCalendar.today)
        #expect(!turns.contains { $0.text.contains("Recent training") })
    }
}

// MARK: - Expectation Tests

struct ExpectationShapeTests {

    @Test func proposesPassesOnTheRightToolAndFailsOtherwise() {
        #expect(verdict(.proposes(.recordWorkout), [.action(.recordWorkout(yesterdayRun))]).passed)
        #expect(!verdict(.proposes(.planStrengthDay), [.action(.recordWorkout(yesterdayRun))]).passed)
        #expect(!verdict(.proposes(.recordWorkout), [.textChunk("Sure")]).passed)
    }

    @Test func noProposalTreatsChatRepliesAsTalk() {
        #expect(verdict(.noProposal, [.action(.reply("What did you do?"))]).passed)
        #expect(!verdict(.noProposal, [.action(.recordWorkout(yesterdayRun))]).passed)
    }

    @Test func noRejectionsFailsOnAnyRejection() {
        #expect(verdict(.noRejections, [.textChunk("ok")]).passed)
        let failed = verdict(.noRejections, [.rejectedToolCall(reason: "bad date")])
        #expect(!failed.passed)
        #expect(failed.detail.contains("bad date"))
    }
}

struct ExpectationReplyTests {

    @Test func replyNotEmptyIgnoresWhitespace() {
        #expect(!verdict(.replyNotEmpty, [.textChunk("  \n")]).passed)
        #expect(verdict(.replyNotEmpty, [.textChunk("Rest.")]).passed)
    }

    @Test func replyAsksQuestionLooksForAQuestionMark() {
        #expect(verdict(.replyAsksQuestion, [.textChunk("How far did you go?")]).passed)
        #expect(!verdict(.replyAsksQuestion, [.textChunk("Logged.")]).passed)
    }

    @Test func mentionsAnyIsCaseInsensitive() {
        #expect(verdict(.replyMentionsAny(["rest"]), [.textChunk("Take a REST day")]).passed)
        #expect(!verdict(.replyMentionsAny(["rest", "easy"]), [.textChunk("Go hard")]).passed)
    }

    @Test func omitsFailsAndNamesWhatItFound() {
        let failed = verdict(.replyOmits(["swim", "bike"]), [.textChunk("Try a Swim")])
        #expect(!failed.passed)
        #expect(failed.detail.contains("swim"))
        #expect(verdict(.replyOmits(["swim"]), [.textChunk("Run easy")]).passed)
    }

    @Test func maxWordsIsInclusive() {
        #expect(verdict(.maxWords(3), [.textChunk("one two three")]).passed)
        #expect(!verdict(.maxWords(2), [.textChunk("one two three")]).passed)
    }
}

struct ExpectationWorkoutTests {

    private let events: [CoachEvent] = [.action(.recordWorkout(yesterdayRun))]

    @Test func dateMatchesByDayOffsetFromScenarioToday() {
        #expect(verdict(.workoutOn(day: -1), events).passed)
        let wrong = verdict(.workoutOn(day: 0), events)
        #expect(!wrong.passed)
        #expect(wrong.detail.contains("2026-10-13"))
    }

    @Test func typeDistanceAndDurationUseTolerances() {
        #expect(verdict(.workoutType(.easyRun), events).passed)
        #expect(!verdict(.workoutType(.tempoRun), events).passed)
        #expect(verdict(.workoutDistance(miles: 5.04), events).passed)
        #expect(!verdict(.workoutDistance(miles: 5.2), events).passed)
        #expect(verdict(.workoutDuration(seconds: 2500), events).passed)
        #expect(!verdict(.workoutDuration(seconds: 2400), events).passed)
    }

    @Test func missingDistanceFails() {
        let noDistance = WorkoutProposal(date: EvalCalendar.today, exerciseType: .walk, durationSeconds: 600)
        #expect(!verdict(.workoutDistance(miles: 1), [.action(.recordWorkout(noDistance))]).passed)
    }

    @Test func ratingsMatchExactlyIncludingUnset() {
        #expect(verdict(.workoutExertion(4), events).passed)
        #expect(verdict(.workoutFeeling(4), events).passed)
        #expect(!verdict(.workoutFeeling(nil), events).passed)
        let unrated = WorkoutProposal(date: EvalCalendar.today, exerciseType: .walk, durationSeconds: 600)
        #expect(verdict(.workoutFeeling(nil), [.action(.recordWorkout(unrated))]).passed)
    }

    @Test func payloadChecksFailOnTheWrongProposalKind() {
        let move = StrengthExerciseUpdateProposal(weekdayIndex: 1, exerciseName: "Squat", kind: .remove, rationale: "")
        let failed = verdict(.workoutType(.easyRun), [.action(.updateStrengthExercise(move))])
        #expect(!failed.passed)
        #expect(failed.detail.contains("update_strength_exercise"))
    }
}

struct ExpectationScheduleTests {

    private let change = ScheduleChangeProposal(
        date: EvalCalendar.day(1), kind: .adjustDistance, distanceMiles: 4, rationale: "tired"
    )

    @Test func dateAndKind() {
        let events: [CoachEvent] = [.action(.suggestScheduleChange(change))]
        #expect(verdict(.scheduleChangeOn(day: 1), events).passed)
        #expect(!verdict(.scheduleChangeOn(day: 2), events).passed)
        #expect(verdict(.scheduleChangeKind(.adjustDistance, .adjustDuration), events).passed)
        #expect(!verdict(.scheduleChangeKind(.remove), events).passed)
    }

    @Test func freeFormCheckReceivesThePayload() {
        let events: [CoachEvent] = [.action(.suggestScheduleChange(change))]
        #expect(verdict(.scheduleChange("short") { .check(($0.distanceMiles ?? 99) < 6, "") }, events).passed)
    }
}

struct ExpectationStrengthTests {

    private let day = StrengthDayProposal(
        weekdayIndex: 2,
        exercises: [
            PlannedStrengthExercise(name: "Front Squat", muscleGroup: .quads, plannedSets: 3, plannedReps: 8),
            PlannedStrengthExercise(name: "Hip Thrust", muscleGroup: .glutes),
        ],
        rationale: "legs"
    )

    @Test func dayAndCount() {
        let events: [CoachEvent] = [.action(.planStrengthDay(day))]
        #expect(verdict(.strengthDayOn("Tuesday"), events).passed)
        #expect(!verdict(.strengthDayOn("Monday"), events).passed)
        #expect(verdict(.strengthDayExerciseCount(1...8), events).passed)
        #expect(!verdict(.strengthDayExerciseCount(1...1), events).passed)
    }

    @Test func updateTargetAndKind() {
        let move = StrengthExerciseUpdateProposal(
            weekdayIndex: 1, exerciseName: "Romanian Deadlift", kind: .moveToDay,
            newWeekdayIndex: 4, rationale: ""
        )
        let events: [CoachEvent] = [.action(.updateStrengthExercise(move))]
        #expect(verdict(.strengthUpdateTargets("Monday", nameContaining: "ROMANIAN"), events).passed)
        #expect(!verdict(.strengthUpdateTargets("Friday", nameContaining: "romanian"), events).passed)
        #expect(verdict(.strengthUpdateKind(.moveToDay, to: "Thursday"), events).passed)
        #expect(!verdict(.strengthUpdateKind(.moveToDay, to: "Friday"), events).passed)
        #expect(!verdict(.strengthUpdateKind(.offload), events).passed)
    }
}

// MARK: - Runner Tests

struct EvalRunnerTests {

    @Test func runsEachScenarioForEverySampleAndRecordsTheModel() async {
        let generator = ScriptedGenerator(modelID: "fake/model", always: [.textChunk("Rest up?")])
        let runner = EvalRunner(generator: generator, samples: 3)
        let record = await runner.run([ScenarioLibrary.recordAskFirst, ScenarioLibrary.chatNoData])
        #expect(record.modelID == "fake/model")
        #expect(record.scenarios.map(\.id) == ["record-ask-first", "chat-no-data"])
        #expect(record.scenarios.allSatisfy { $0.samples.count == 3 })
        #expect(await generator.callCount == 6)
    }

    @Test func passRatesReflectVaryingSamples() async {
        // Alternate a right and a wrong answer: a 50% scenario.
        let generator = ScriptedGenerator { _, index in
            index.isMultiple(of: 2) ? [.action(.recordWorkout(yesterdayRun))] : [.textChunk("Sure")]
        }
        let s = scenario([.proposes(.recordWorkout), .workoutOn(day: -1)])
        let record = await EvalRunner(generator: generator, samples: 4).run([s])
        let result = record.scenarios[0]
        #expect(result.passCount == 2)
        #expect(result.passRate == 0.5)
        #expect(result.checkSummaries.map(\.passes) == [2, 2])
        #expect(record.passRate == 0.5)
    }

    @Test func generationErrorsFailTheSampleWithoutStoppingTheRun() async {
        struct Boom: Error {}
        let generator = ScriptedGenerator { _, _ in throw Boom() }
        let record = await EvalRunner(generator: generator, samples: 2).run([scenario([.replyNotEmpty])])
        let samples = record.scenarios[0].samples
        #expect(samples.count == 2)
        #expect(samples.allSatisfy { $0.error != nil && !$0.passed })
    }

    @Test func gradeRecordsProposalSummaryAndChecks() {
        let s = scenario([.proposes(.recordWorkout), .noRejections])
        let result = EvalRunner.grade(TurnTranscript.folding([.action(.recordWorkout(yesterdayRun))]), for: s)
        #expect(result.passed)
        #expect(result.checks.map(\.label) == ["proposes record_workout", "no rejected tool calls"])
        #expect(result.proposal?.hasPrefix("record_workout 2026-10-13 Tue") == true)
    }

    @Test func samplesAreClampedToAtLeastOne() {
        #expect(EvalRunner(generator: ScriptedGenerator(always: []), samples: 0).samples == 1)
    }

    @Test func progressReportsStartAndFinishForEachSample() async {
        let events = EventLog()
        let runner = EvalRunner(generator: ScriptedGenerator(always: [.textChunk("x")]), samples: 2)
        _ = await runner.run([scenario([])]) { events.append($0) }
        #expect(events.count == 4)
    }
}

/// Thread-safe event counter for the progress callback.
private final class EventLog: @unchecked Sendable {
    private let lock = NSLock()
    private var events: [EvalProgress] = []
    func append(_ event: EvalProgress) { lock.withLock { events.append(event) } }
    var count: Int { lock.withLock { events.count } }
}

// MARK: - Run Record Tests

struct RunRecordTests {

    private func record(_ rates: [String: [Bool]], note: String? = nil) -> RunRecord {
        RunRecord(
            startedAt: Date(timeIntervalSince1970: 1_800_000_000),
            gitCommit: "abc1234", note: note, modelID: "m", config: .chat,
            samplesPerScenario: 2,
            scenarios: rates.keys.sorted().map { id in
                ScenarioResult(id: id, title: id, tags: [], samples: rates[id]!.map { passed in
                    SampleResult(
                        checks: [CheckResult(label: "c", passed: passed, detail: "")],
                        reply: "r", proposal: nil, rejections: [],
                        stats: TurnStats(promptTokens: 10, generatedTokens: 20, promptSeconds: 1, generateSeconds: 2)
                    )
                })
            }
        )
    }

    @Test func jsonRoundTripPreservesResults() throws {
        let original = record(["a": [true, false]], note: "baseline")
        let decoded = try RunRecord.decode(original.jsonData())
        #expect(decoded.scenarios == original.scenarios)
        #expect(decoded.note == "baseline")
        #expect(decoded.gitCommit == "abc1234")
        #expect(decoded.startedAt == original.startedAt)
        #expect(decoded.config.temperature == GenerationConfig.chat.temperature)
    }

    @Test func meanTokensPerSecondAveragesSamples() {
        #expect(record(["a": [true, true]]).scenarios[0].meanTokensPerSecond == 10)
    }

    @Test func comparisonPairsScenariosAndShowsAdditions() {
        let before = record(["a": [true, false], "b": [true, true]])
        let after = record(["a": [true, true], "c": [false, false]])
        let rows = RunComparison.rows(before: before, after: after)
        #expect(rows.map(\.id) == ["a", "b", "c"])
        #expect(rows[0].change == 0.5)
        #expect(rows[1].after == nil && rows[1].change == nil)
        #expect(rows[2].before == nil && rows[2].after == 0)
    }

    @Test func formattersMentionEveryScenario() {
        let before = record(["a": [true, false]])
        let after = record(["a": [true, true]])
        let summary = ReportFormatter.summary(before)
        #expect(summary.contains("a"))
        #expect(summary.contains("1/2"))
        let comparison = ReportFormatter.comparison(RunComparison.rows(before: before, after: after), before: before, after: after)
        #expect(comparison.contains("+50%"))
    }

    @Test func failureDetailListsOnlyFailedChecks() {
        let sample = SampleResult(
            checks: [
                CheckResult(label: "good", passed: true, detail: ""),
                CheckResult(label: "bad", passed: false, detail: "got 3"),
            ],
            reply: "hello", proposal: nil, rejections: ["oops"]
        )
        let detail = ReportFormatter.failureDetail(sample)
        #expect(detail.contains("bad — got 3"))
        #expect(!detail.contains("good"))
        #expect(detail.contains("oops"))
    }
}

// MARK: - Proposal Summary Tests

struct ProposalSummaryTests {

    @Test func workoutLineIncludesEveryRecordedField() {
        let line = ProposalSummary.describe(.recordWorkout(yesterdayRun))
        #expect(line == "record_workout 2026-10-13 Tue · Easy Run · 5.0 mi · 42:00 · RPE 4 · feeling 4")
    }

    @Test func clockSwitchesToHoursFromSixtyMinutes() {
        #expect(ProposalSummary.clock(59 * 60) == "59:00")
        #expect(ProposalSummary.clock(3725) == "1:02:05")
    }

    @Test func strengthDayListsLiftsWithPlans() {
        let day = StrengthDayProposal(
            weekdayIndex: 5,
            exercises: [PlannedStrengthExercise(name: "Face Pull", muscleGroup: .shoulders, plannedSets: 3, plannedReps: 15)],
            rationale: ""
        )
        #expect(ProposalSummary.describe(.planStrengthDay(day)) == "plan_strength_day Friday: Face Pull (Shoulders) 3x15")
    }
}

// MARK: - Scenario Library Tests

struct ScenarioLibraryTests {

    @Test func idsAreUnique() {
        let ids = ScenarioLibrary.all.map(\.id)
        #expect(Set(ids).count == ids.count)
    }

    @Test func everyScenarioHasExpectationsAndAMessage() {
        for scenario in ScenarioLibrary.all {
            #expect(!scenario.expectations.isEmpty, "\(scenario.id) has no expectations")
            #expect(!scenario.athleteMessage.isEmpty, "\(scenario.id) has no message")
            #expect(!scenario.tags.isEmpty, "\(scenario.id) has no tags")
        }
    }

    @Test func historyNeverContainsSystemTurns() {
        // The prompt builder adds the system turn; a scripted one would double it.
        for scenario in ScenarioLibrary.all {
            #expect(!scenario.history.contains { $0.role == .system }, "\(scenario.id)")
        }
    }

    @Test func selectFiltersByIdAndTag() {
        #expect(ScenarioLibrary.select(ids: ["strength-move"]).map(\.id) == ["strength-move"])
        let strength = ScenarioLibrary.select(tag: "strength")
        #expect(!strength.isEmpty && strength.allSatisfy { $0.tags.contains("strength") })
        #expect(ScenarioLibrary.select(ids: ["strength-move"], tag: "record").isEmpty)
        #expect(ScenarioLibrary.select().count == ScenarioLibrary.all.count)
    }

    @Test func lookupByID() {
        #expect(ScenarioLibrary.scenario(id: "record-yesterday")?.title == "Record a fully described workout")
        #expect(ScenarioLibrary.scenario(id: "nope") == nil)
        #expect(ScenarioLibrary.tags.contains("invariant"))
    }

    @Test func addingASecondNewLiftFailsStrengthAddOne() {
        let day = StrengthDayProposal(
            weekdayIndex: 5,
            exercises: [
                PlannedStrengthExercise(name: "Face Pull", muscleGroup: .shoulders, plannedSets: 3, plannedReps: 15),
                PlannedStrengthExercise(name: "Shrug", muscleGroup: .back, plannedSets: 3, plannedReps: 12),
            ],
            rationale: ""
        )
        let result = EvalRunner.grade(
            TurnTranscript.folding([.action(.planStrengthDay(day))]), for: ScenarioLibrary.strengthAddOne
        )
        #expect(!result.passed)
    }

    @Test func perfectAnswersPassTheirOwnScenarios() {
        // Guards the scenarios themselves: a hand-written ideal answer must
        // score 100%, or the expectation (not the model) is wrong.
        let ideal: [String: [CoachEvent]] = [
            "record-yesterday": [.action(.recordWorkout(yesterdayRun))],
            "record-ask-first": [.action(.reply("Happy to! What did you do, and when?"))],
            "strength-move": [.action(.updateStrengthExercise(StrengthExerciseUpdateProposal(
                weekdayIndex: 1, exerciseName: "Romanian Deadlift", kind: .moveToDay,
                newWeekdayIndex: 4, rationale: "as asked"
            )))],
            "strength-add-one": [.action(.planStrengthDay(StrengthDayProposal(
                weekdayIndex: 5,
                exercises: [
                    // Re-listing an existing lift is fine: the applier skips it.
                    PlannedStrengthExercise(name: "Pull-Up", muscleGroup: .back, plannedSets: 4, plannedReps: 8),
                    PlannedStrengthExercise(name: "Face Pull", muscleGroup: .shoulders, plannedSets: 3, plannedReps: 15),
                ],
                rationale: "as asked"
            )))],
            "schedule-shorten-tomorrow": [.action(.suggestScheduleChange(ScheduleChangeProposal(
                date: EvalCalendar.day(1), kind: .adjustDistance, distanceMiles: 4, rationale: "legs are toast"
            )))],
        ]
        for (id, events) in ideal {
            let scenario = ScenarioLibrary.scenario(id: id)!
            let result = EvalRunner.grade(TurnTranscript.folding(events), for: scenario)
            #expect(result.passed, "\(id): \(ReportFormatter.failureDetail(result))")
        }
    }
}
