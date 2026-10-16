//
//  CoachToolTests.swift
//  AICoachCoreTests
//
//  Covers the tool vocabulary, its JSON schemas, the raw-tool-call decoder,
//  and conversational prompt assembly.
//

import Foundation
import Testing
@testable import AICoachCore

// MARK: - Tool Schema Tests

struct CoachToolSchemaTests {

    /// Fixed "today" for schema assertions. The schemas name the current date
    /// in their date descriptions, so they have to be built against one.
    private let today = Date(timeIntervalSince1970: 1_792_004_400)

    private var all: [[String: any Sendable]] { CoachToolSchemas.all(today: today) }
    private var suggestScheduleChange: [String: any Sendable] {
        CoachToolSchemas.suggestScheduleChange(today: today)
    }
    private var planStrengthDay: [String: any Sendable] {
        CoachToolSchemas.planStrengthDay
    }
    private var recordWorkout: [String: any Sendable] {
        CoachToolSchemas.recordWorkout(today: today)
    }

    /// Reads the `function` sub-object out of a tool envelope.
    private func fn(_ schema: [String: any Sendable]) -> [String: any Sendable] {
        schema["function"] as! [String: any Sendable]
    }

    private func parameters(_ schema: [String: any Sendable]) -> [String: any Sendable] {
        fn(schema)["parameters"] as! [String: any Sendable]
    }

    private func properties(_ schema: [String: any Sendable]) -> [String: any Sendable] {
        parameters(schema)["properties"] as! [String: any Sendable]
    }

    private func required(_ schema: [String: any Sendable]) -> [String] {
        parameters(schema)["required"] as! [String]
    }

    @Test func everyToolHasASchema() {
        #expect(all.count == CoachTool.allCases.count)
    }

    @Test func schemaNamesMatchToolRawValues() {
        let names = all.map { fn($0)["name"] as! String }
        #expect(Set(names) == Set(CoachTool.allCases.map(\.rawValue)))
    }

    @Test func chatIsOfferedFirst() {
        // The model should read "just reply" as the default option.
        #expect(fn(all[0])["name"] as! String == CoachTool.chat.rawValue)
    }

    @Test func everySchemaIsAFunctionEnvelope() {
        for schema in all {
            #expect(schema["type"] as! String == "function")
            #expect(parameters(schema)["type"] as! String == "object")
            #expect(!(fn(schema)["description"] as! String).isEmpty)
        }
    }

    @Test func everyPropertyIsDescribed() {
        for schema in all {
            for (name, property) in properties(schema) {
                let property = property as! [String: any Sendable]
                let description = property["description"] as? String
                #expect(description?.isEmpty == false, "\(name) needs a description")
            }
        }
    }

    @Test func requiredFieldsExistAsProperties() {
        for schema in all {
            let names = Set(properties(schema).keys)
            for field in required(schema) {
                #expect(names.contains(field), "required \(field) is not a property")
            }
        }
    }

    @Test func chatRequiresOnlyAMessage() {
        #expect(required(CoachToolSchemas.chat) == ["message"])
    }

    @Test func scheduleChangeRequiresDateKindAndRationale() {
        #expect(Set(required(suggestScheduleChange))
            == Set(["date", "kind", "rationale"]))
    }

    @Test func scheduleChangeKindEnumeratesEveryCase() {
        let kind = properties(suggestScheduleChange)["kind"]
            as! [String: any Sendable]
        #expect(kind["enum"] as! [String] == ScheduleChangeKind.allCases.map(\.rawValue))
    }

    @Test func exerciseTypeEnumeratesEveryCase() {
        for schema in [suggestScheduleChange, recordWorkout] {
            let type = properties(schema)["exercise_type"] as! [String: any Sendable]
            #expect(type["enum"] as! [String] == CoachExerciseType.allCases.map(\.rawValue))
        }
    }

    @Test func recordWorkoutRequiresOnlyDateAndType() {
        // Everything else is something the athlete may simply not have said.
        #expect(Set(required(recordWorkout)) == Set(["date", "exercise_type"]))
    }

    @Test func strengthDayRequiresWeekdayExercisesAndRationale() {
        #expect(Set(required(planStrengthDay)) == Set(["weekday", "exercises", "rationale"]))
    }

    @Test func strengthDayWeekdayEnumeratesEveryDayName() {
        let weekday = properties(planStrengthDay)["weekday"] as! [String: any Sendable]
        #expect(weekday["enum"] as! [String] == StrengthDayProposal.weekdayNames)
    }

    @Test func strengthDayMuscleGroupEnumeratesEveryCase() {
        let group = itemProperties(planStrengthDay)["muscle_group"] as! [String: any Sendable]
        #expect(group["enum"] as! [String] == CoachMuscleGroup.allCases.map(\.rawValue))
    }

    @Test func strengthDayExercisesIsABoundedArrayOfObjects() {
        let exercises = properties(planStrengthDay)["exercises"] as! [String: any Sendable]
        #expect(exercises["type"] as! String == "array")
        #expect(exercises["minItems"] as! Int == 1)
        #expect(exercises["maxItems"] as! Int == StrengthDayProposal.maxExercises)
        let items = exerciseItems(planStrengthDay)
        #expect(items["type"] as! String == "object")
        #expect(items["required"] as! [String] == ["name", "muscle_group"])
    }

    @Test func strengthDayExerciseItemPropertiesAreAllDescribed() {
        for (name, property) in itemProperties(planStrengthDay) {
            let property = property as! [String: any Sendable]
            let description = property["description"] as? String
            #expect(description?.isEmpty == false, "item \(name) needs a description")
        }
    }

    @Test func strengthDayDescriptionAsksForTheWholeDayInOneCall() {
        // A full-body request split across seven calls would lose six of them
        // to first-proposal-wins, so batching has to be the schema's ask.
        let description = fn(planStrengthDay)["description"] as! String
        #expect(description.contains("ONE call"))
        #expect(description.lowercased().contains("muscle group"))
    }

    /// Reads the `items` sub-schema out of the tool's `exercises` property.
    private func exerciseItems(_ schema: [String: any Sendable]) -> [String: any Sendable] {
        let exercises = properties(schema)["exercises"] as! [String: any Sendable]
        return exercises["items"] as! [String: any Sendable]
    }

    /// Reads the properties of the `exercises` array's item object. Unlike the
    /// top-level helpers, the item schema is not wrapped in a function
    /// envelope, so its `properties` sit at its own top level.
    private func itemProperties(_ schema: [String: any Sendable]) -> [String: any Sendable] {
        exerciseItems(schema)["properties"] as! [String: any Sendable]
    }

    @Test func dateDescriptionsNameTodayRatherThanAnExample() {
        // A static example date ("e.g. 2026-04-06") was being copied straight
        // into tool calls, so every date argument now carries today instead.
        let iso = AICoachPromptBuilder.isoDate(today)
        for schema in [suggestScheduleChange, recordWorkout] {
            let date = properties(schema)["date"] as! [String: any Sendable]
            let description = date["description"] as! String
            #expect(description.contains("YYYY-MM-DD"))
            #expect(description.contains(iso))
        }
    }

    @Test func recordWorkoutAsksTheModelToGatherFieldsFirst() {
        let description = fn(recordWorkout)["description"] as! String
        #expect(description.contains("chat tool"))
        #expect(description.lowercased().contains("how far or how long"))
    }

    @Test func recordWorkoutKeepsFeelingAndExertionSeparate() {
        let props = properties(recordWorkout)
        let exertion = (props["perceived_exertion"] as! [String: any Sendable])["description"] as! String
        let feeling = (props["feeling"] as! [String: any Sendable])["description"] as! String
        #expect(exertion.contains("1 (very easy) to 10"))
        #expect(feeling.contains("1 (very weak) to 5"))
        // Each must tell the model the other is not derivable from it.
        #expect(exertion.lowercased().contains("separate"))
        #expect(feeling.lowercased().contains("separate"))
        // And that omitting is correct.
        #expect(exertion.contains("Omit"))
        #expect(feeling.contains("Omit"))
    }
}

// MARK: - Tool Decoder Tests

struct CoachToolDecoderTests {

    /// 2026-04-06 in the current time zone, matching the decoder's formatter.
    private func day(_ string: String) -> Date {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f.date(from: string)!
    }

    // MARK: chat

    @Test func decodesChatReply() throws {
        let action = try CoachToolDecoder.decode(
            name: "chat",
            arguments: ["message": "Nice work this week."]
        )
        #expect(action == .reply("Nice work this week."))
        #expect(action.tool == .chat)
    }

    @Test func chatWithoutMessageIsRejected() {
        #expect(throws: CoachToolDecodeError.missingArgument("message")) {
            try CoachToolDecoder.decode(name: "chat", arguments: [:])
        }
    }

    @Test func blankChatMessageIsTreatedAsMissing() {
        #expect(throws: CoachToolDecodeError.missingArgument("message")) {
            try CoachToolDecoder.decode(name: "chat", arguments: ["message": "   \n "])
        }
    }

    @Test func unknownToolIsRejected() {
        #expect(throws: CoachToolDecodeError.unknownTool("delete_everything")) {
            try CoachToolDecoder.decode(name: "delete_everything", arguments: [:])
        }
    }

    // MARK: record_workout

    @Test func decodesFullWorkoutProposal() throws {
        let action = try CoachToolDecoder.decode(
            name: "record_workout",
            arguments: [
                "date": "2026-04-06",
                "exercise_type": "Easy Run",
                "distance_miles": 5.0,
                "duration_seconds": 2700,
                "perceived_exertion": 4,
                "feeling": 4,
                "notes": "legs felt fresh",
            ]
        )
        #expect(action == .recordWorkout(WorkoutProposal(
            date: day("2026-04-06"),
            exerciseType: .easyRun,
            distanceMiles: 5.0,
            durationSeconds: 2700,
            perceivedExertion: 4,
            feeling: 4,
            notes: "legs felt fresh"
        )))
    }

    @Test func workoutOmitsUnstatedFields() throws {
        let action = try CoachToolDecoder.decode(
            name: "record_workout",
            arguments: ["date": "2026-04-06", "exercise_type": "Run", "distance_miles": 5.0]
        )
        guard case .recordWorkout(let proposal) = action else {
            Issue.record("expected a workout proposal")
            return
        }
        #expect(proposal.durationSeconds == nil)
        #expect(proposal.perceivedExertion == nil)
        #expect(proposal.feeling == nil)
        #expect(proposal.notes == nil)
    }

    @Test func workoutNeedsADistanceOrADuration() {
        // "Can you record a workout for me" gives the model neither, and a
        // proposal built from a guessed date is worse than a follow-up question.
        #expect(throws: CoachToolDecodeError
            .missingArgument("distance_miles or duration_seconds")) {
            try CoachToolDecoder.decode(
                name: "record_workout",
                arguments: ["date": "2026-04-06", "exercise_type": "Run"]
            )
        }
    }

    @Test func workoutAcceptsEitherSizeAlone() throws {
        for size in ["distance_miles", "duration_seconds"] {
            let action = try CoachToolDecoder.decode(
                name: "record_workout",
                arguments: ["date": "2026-04-06", "exercise_type": "Run", size: 30]
            )
            guard case .recordWorkout = action else {
                Issue.record("expected a workout proposal for \(size)")
                return
            }
        }
    }

    @Test func workoutKeepsFeelingAndExertionIndependent() throws {
        // All four combinations survive decoding without one implying the other.
        let combinations: [(Int?, Int?)] = [(nil, nil), (8, nil), (nil, 2), (8, 2)]
        for (exertion, feeling) in combinations {
            var arguments: [String: Any] = [
                "date": "2026-04-06", "exercise_type": "Run", "distance_miles": 5.0,
            ]
            if let exertion { arguments["perceived_exertion"] = exertion }
            if let feeling { arguments["feeling"] = feeling }
            let action = try CoachToolDecoder.decode(name: "record_workout", arguments: arguments)
            guard case .recordWorkout(let proposal) = action else {
                Issue.record("expected a workout proposal")
                return
            }
            #expect(proposal.perceivedExertion == exertion)
            #expect(proposal.feeling == feeling)
        }
    }

    @Test func workoutAcceptsNumbersAsStringsAndIntegers() throws {
        let action = try CoachToolDecoder.decode(
            name: "record_workout",
            arguments: [
                "date": "2026-04-06",
                "exercise_type": "Run",
                "distance_miles": "5.5",
                "duration_seconds": 1800,
            ]
        )
        guard case .recordWorkout(let proposal) = action else {
            Issue.record("expected a workout proposal")
            return
        }
        #expect(proposal.distanceMiles == 5.5)
        #expect(proposal.durationSeconds == 1800)
    }

    @Test func workoutRejectsOutOfRangeRatings() {
        // Clamping would put a number the athlete never gave into their history.
        for (key, value) in [("perceived_exertion", 15), ("feeling", 9), ("feeling", 0)] {
            #expect(throws: CoachToolDecodeError.self) {
                try CoachToolDecoder.decode(
                    name: "record_workout",
                    arguments: [
                        "date": "2026-04-06",
                        "exercise_type": "Run",
                        "distance_miles": 5.0,
                        key: value,
                    ]
                )
            }
        }
    }

    @Test func workoutRejectsUnknownExerciseType() {
        #expect(throws: CoachToolDecodeError.self) {
            try CoachToolDecoder.decode(
                name: "record_workout",
                arguments: ["date": "2026-04-06", "exercise_type": "Quidditch"]
            )
        }
    }

    @Test func workoutRejectsMalformedDate() {
        #expect(throws: CoachToolDecodeError.self) {
            try CoachToolDecoder.decode(
                name: "record_workout",
                arguments: ["date": "last Tuesday", "exercise_type": "Run"]
            )
        }
    }

    @Test func workoutRejectsNegativeDistance() {
        #expect(throws: CoachToolDecodeError.self) {
            try CoachToolDecoder.decode(
                name: "record_workout",
                arguments: [
                    "date": "2026-04-06", "exercise_type": "Run", "distance_miles": -3.0,
                ]
            )
        }
    }

    @Test func workoutRequiresExerciseType() {
        #expect(throws: CoachToolDecodeError.missingArgument("exercise_type")) {
            try CoachToolDecoder.decode(
                name: "record_workout",
                arguments: ["date": "2026-04-06"]
            )
        }
    }

    // MARK: suggest_schedule_change

    @Test func decodesScheduleChange() throws {
        let action = try CoachToolDecoder.decode(
            name: "suggest_schedule_change",
            arguments: [
                "date": "2026-04-08",
                "kind": "adjust_distance",
                "distance_miles": 4.0,
                "rationale": "Your RPE has been climbing.",
            ]
        )
        #expect(action == .suggestScheduleChange(ScheduleChangeProposal(
            date: day("2026-04-08"),
            kind: .adjustDistance,
            distanceMiles: 4.0,
            rationale: "Your RPE has been climbing."
        )))
    }

    @Test func scheduleChangeRequiresTheValueItChanges() {
        let cases: [(String, String)] = [
            ("adjust_distance", "distance_miles"),
            ("adjust_duration", "duration_seconds"),
            ("change_type", "exercise_type"),
            ("add", "exercise_type"),
        ]
        for (kind, missing) in cases {
            #expect(throws: CoachToolDecodeError.missingArgument(missing)) {
                try CoachToolDecoder.decode(
                    name: "suggest_schedule_change",
                    arguments: ["date": "2026-04-08", "kind": kind, "rationale": "because"]
                )
            }
        }
    }

    @Test func removeNeedsNoExtraValue() throws {
        let action = try CoachToolDecoder.decode(
            name: "suggest_schedule_change",
            arguments: ["date": "2026-04-08", "kind": "remove", "rationale": "Too much load."]
        )
        guard case .suggestScheduleChange(let proposal) = action else {
            Issue.record("expected a schedule change")
            return
        }
        #expect(proposal.kind == .remove)
    }

    @Test func scheduleChangeRejectsUnknownKind() {
        #expect(throws: CoachToolDecodeError.self) {
            try CoachToolDecoder.decode(
                name: "suggest_schedule_change",
                arguments: ["date": "2026-04-08", "kind": "reverse_time", "rationale": "x"]
            )
        }
    }

    @Test func scheduleChangeRequiresRationale() {
        #expect(throws: CoachToolDecodeError.missingArgument("rationale")) {
            try CoachToolDecoder.decode(
                name: "suggest_schedule_change",
                arguments: ["date": "2026-04-08", "kind": "remove"]
            )
        }
    }

    // MARK: plan_strength_day

    /// A valid two-exercise argument object, mutable per test.
    private func strengthDayArguments() -> [String: Any] {
        [
            "weekday": "Friday",
            "exercises": [
                ["name": "Barbell Back Squat", "muscle_group": "Quads", "sets": 3, "reps": 5],
                ["name": "Barbell Bench Press", "muscle_group": "Chest"],
            ],
            "rationale": "Full body coverage for Friday.",
        ]
    }

    @Test func decodesStrengthDay() throws {
        let action = try CoachToolDecoder.decode(
            name: "plan_strength_day",
            arguments: strengthDayArguments()
        )
        #expect(action == .planStrengthDay(StrengthDayProposal(
            weekdayIndex: 5,
            exercises: [
                PlannedStrengthExercise(
                    name: "Barbell Back Squat", muscleGroup: .quads,
                    plannedSets: 3, plannedReps: 5
                ),
                PlannedStrengthExercise(name: "Barbell Bench Press", muscleGroup: .chest),
            ],
            rationale: "Full body coverage for Friday."
        )))
        #expect(action.tool == .planStrengthDay)
    }

    @Test func strengthDayWeekdayIsCaseInsensitive() throws {
        var arguments = strengthDayArguments()
        arguments["weekday"] = "friday"
        let action = try CoachToolDecoder.decode(
            name: "plan_strength_day", arguments: arguments
        )
        guard case .planStrengthDay(let proposal) = action else {
            Issue.record("expected a strength day proposal")
            return
        }
        #expect(proposal.weekdayIndex == 5)
    }

    @Test func strengthDayRejectsUnknownWeekday() {
        var arguments = strengthDayArguments()
        arguments["weekday"] = "Freeday"
        #expect(throws: CoachToolDecodeError.self) {
            try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
        }
    }

    @Test func strengthDayRequiresAWeekday() {
        var arguments = strengthDayArguments()
        arguments.removeValue(forKey: "weekday")
        #expect(throws: CoachToolDecodeError.missingArgument("weekday")) {
            try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
        }
    }

    @Test func strengthDayRequiresExercises() {
        var arguments = strengthDayArguments()
        arguments.removeValue(forKey: "exercises")
        #expect(throws: CoachToolDecodeError.missingArgument("exercises")) {
            try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
        }
    }

    @Test func strengthDayRejectsAnEmptyExerciseList() {
        var arguments = strengthDayArguments()
        arguments["exercises"] = [[String: Any]]()
        #expect(throws: CoachToolDecodeError.self) {
            try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
        }
    }

    @Test func strengthDayCapsTheExerciseList() {
        var arguments = strengthDayArguments()
        arguments["exercises"] = (0..<StrengthDayProposal.maxExercises + 1).map {
            ["name": "Exercise \($0)", "muscle_group": "Core"]
        }
        #expect(throws: CoachToolDecodeError.self) {
            try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
        }
    }

    @Test func strengthDayAcceptsTheExerciseCapExactly() throws {
        var arguments = strengthDayArguments()
        arguments["exercises"] = (0..<StrengthDayProposal.maxExercises).map {
            ["name": "Exercise \($0)", "muscle_group": "Core"]
        }
        let action = try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
        guard case .planStrengthDay(let proposal) = action else {
            Issue.record("expected a strength day proposal")
            return
        }
        #expect(proposal.exercises.count == StrengthDayProposal.maxExercises)
    }

    @Test func strengthDayMuscleGroupIsCaseInsensitive() throws {
        var arguments = strengthDayArguments()
        arguments["exercises"] = [["name": "Curl", "muscle_group": "biceps"]]
        let action = try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
        guard case .planStrengthDay(let proposal) = action else {
            Issue.record("expected a strength day proposal")
            return
        }
        #expect(proposal.exercises.first?.muscleGroup == .biceps)
    }

    @Test func strengthDayRejectsUnknownMuscleGroup() {
        var arguments = strengthDayArguments()
        arguments["exercises"] = [["name": "Face Pull", "muscle_group": "Face"]]
        #expect(throws: CoachToolDecodeError.self) {
            try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
        }
    }

    @Test func strengthDayRequiresSetsAndRepsTogether() {
        // A plan exists only when both are set; one alone is a mistake, not a
        // default to invent.
        for (present, missing) in [("sets", "reps"), ("reps", "sets")] {
            var arguments = strengthDayArguments()
            arguments["exercises"] = [["name": "Squat", "muscle_group": "Quads", present: 3]]
            #expect(throws: CoachToolDecodeError.missingArgument(missing)) {
                try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
            }
        }
    }

    @Test func strengthDayRejectsOutOfRangePlanNumbers() {
        // Rejected, never clamped — same rule as the subjective ratings.
        for (key, value) in [("sets", 0), ("sets", 21), ("reps", 0), ("reps", 101)] {
            var exercise: [String: Any] = [
                "name": "Squat", "muscle_group": "Quads", "sets": 3, "reps": 8,
            ]
            exercise[key] = value
            var arguments = strengthDayArguments()
            arguments["exercises"] = [exercise]
            #expect(throws: CoachToolDecodeError.self) {
                try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
            }
        }
    }

    @Test func strengthDayAcceptsPlanNumbersAsStrings() throws {
        var arguments = strengthDayArguments()
        arguments["exercises"] = [[
            "name": "Squat", "muscle_group": "Quads", "sets": "3", "reps": "5",
        ]]
        let action = try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
        guard case .planStrengthDay(let proposal) = action else {
            Issue.record("expected a strength day proposal")
            return
        }
        #expect(proposal.exercises.first?.plannedSets == 3)
        #expect(proposal.exercises.first?.plannedReps == 5)
    }

    @Test func strengthDayRejectsBlankExerciseNames() {
        var arguments = strengthDayArguments()
        arguments["exercises"] = [["name": "   ", "muscle_group": "Core"]]
        #expect(throws: CoachToolDecodeError.missingArgument("name")) {
            try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
        }
    }

    @Test func strengthDayRequiresRationale() {
        var arguments = strengthDayArguments()
        arguments.removeValue(forKey: "rationale")
        #expect(throws: CoachToolDecodeError.missingArgument("rationale")) {
            try CoachToolDecoder.decode(name: "plan_strength_day", arguments: arguments)
        }
    }
}

// MARK: - Workout Proposal Codable Tests

struct CoachProposalCodableTests {

    @Test func workoutProposalRoundTripsEveryRatingCombination() throws {
        let combinations: [(Int?, Int?)] = [(nil, nil), (7, nil), (nil, 3), (7, 3)]
        for (exertion, feeling) in combinations {
            let original = WorkoutProposal(
                date: Date(timeIntervalSince1970: 1_800_000_000),
                exerciseType: .tempoRun,
                distanceMiles: 6.2,
                durationSeconds: 2400,
                perceivedExertion: exertion,
                feeling: feeling,
                notes: nil
            )
            let data = try JSONEncoder().encode(original)
            let decoded = try JSONDecoder().decode(WorkoutProposal.self, from: data)
            #expect(decoded == original)
            #expect(decoded.perceivedExertion == exertion)
            #expect(decoded.feeling == feeling)
        }
    }

    @Test func scheduleChangeProposalRoundTrips() throws {
        let original = ScheduleChangeProposal(
            date: Date(timeIntervalSince1970: 1_800_000_000),
            kind: .changeType,
            exerciseType: .recoveryRun,
            rationale: "Back off after Saturday."
        )
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(ScheduleChangeProposal.self, from: data) == original)
    }

    @Test func strengthDayProposalRoundTrips() throws {
        let original = StrengthDayProposal(
            weekdayIndex: 5,
            exercises: [
                PlannedStrengthExercise(
                    name: "Barbell Back Squat", muscleGroup: .quads,
                    plannedSets: 3, plannedReps: 5
                ),
                PlannedStrengthExercise(name: "Plank", muscleGroup: .core),
            ],
            rationale: "Legs and trunk."
        )
        let data = try JSONEncoder().encode(original)
        #expect(try JSONDecoder().decode(StrengthDayProposal.self, from: data) == original)
    }

    @Test func strengthDayWeekdayNameResolvesTheLane() {
        #expect(StrengthDayProposal(weekdayIndex: 5, exercises: [], rationale: "").weekdayName == "Friday")
        // An out-of-range index from model data reads as a label, not a crash.
        #expect(StrengthDayProposal(weekdayIndex: 9, exercises: [], rationale: "").weekdayName == "Day 9")
    }

    @Test func actionReportsItsTool() {
        #expect(CoachAction.reply("hi").tool == .chat)
        #expect(CoachAction.recordWorkout(WorkoutProposal(
            date: Date(), exerciseType: .run
        )).tool == .recordWorkout)
        #expect(CoachAction.suggestScheduleChange(ScheduleChangeProposal(
            date: Date(), kind: .remove, rationale: "x"
        )).tool == .suggestScheduleChange)
        #expect(CoachAction.planStrengthDay(StrengthDayProposal(
            weekdayIndex: 5, exercises: [], rationale: "x"
        )).tool == .planStrengthDay)
    }
}

// MARK: - Chat Prompt Tests

struct CoachChatPromptTests {

    /// Fixed "today" so the calendar anchor in the system turn is assertable.
    /// 2026-10-14, a Wednesday, in the current time zone.
    private let today = Date(timeIntervalSince1970: 1_792_004_400)

    private func chatTurns(for request: CoachChatRequest) -> [CoachMessage] {
        AICoachPromptBuilder.buildChatTurns(for: request, today: today)
    }

    private var preamble: String {
        AICoachPromptBuilder.chatSystemPreamble(today: today)
    }

    private func request(
        messages: [CoachMessage],
        context: CoachingRequest? = nil
    ) -> CoachChatRequest {
        CoachChatRequest(messages: messages, context: context)
    }

    private func sampleContext(metric: Bool = false) -> CoachingRequest {
        CoachingRequest(
            recentWorkouts: [
                CoachWorkout(
                    date: Date(timeIntervalSince1970: 1_800_000_000),
                    type: .easyRun,
                    distanceMiles: 4.0,
                    durationSeconds: 2100,
                    feeling: 4,
                    perceivedExertion: 3,
                    notes: ""
                )
            ],
            upcomingExercises: [
                CoachExercise(
                    scheduledDate: Date(timeIntervalSince1970: 1_800_200_000),
                    type: .tempoRun,
                    distanceMiles: 6.0,
                    durationSeconds: 2400
                )
            ],
            useMetricUnits: metric
        )
    }

    @Test func systemTurnComesFirstAndOnlyOnce() {
        let turns = chatTurns(for: request(messages: [
            CoachMessage(role: .user, text: "hi"),
            CoachMessage(role: .coach, text: "hello"),
            CoachMessage(role: .user, text: "again"),
        ]))
        #expect(turns.first?.role == .system)
        #expect(turns.first?.text == preamble)
        #expect(turns.filter { $0.role == .system }.count == 1)
    }

    @Test func chatPreambleIsNotTheOneShotPreamble() {
        // The one-shot preamble mandates a bullet list; conversation must not.
        #expect(preamble != AICoachPromptBuilder.systemPreamble)
        #expect(!preamble.contains("3–5 bullet points"))
    }

    @Test func chatPreambleStatesTheRatingsAreIndependent() {
        #expect(preamble.contains("RPE"))
        #expect(preamble.contains("independent"))
        #expect(preamble.contains("either may be missing"))
    }

    @Test func chatPreambleAnchorsTodaysDate() {
        // Without this the model had no clock at all and dated workouts from
        // whatever example date it had last seen.
        let iso = AICoachPromptBuilder.isoDate(today)
        #expect(preamble.contains("Today is \(iso) Wednesday"))
        #expect(preamble.contains("\"today\" is \(iso)"))
    }

    @Test func chatPreambleNamesYesterdayAndTomorrow() {
        #expect(preamble.contains("Yesterday was 2026-10-13 Tuesday"))
        #expect(preamble.contains("tomorrow is 2026-10-15 Thursday"))
    }

    @Test func chatPreambleRecomputesTheAnchorPerTurn() {
        let laterPreamble = AICoachPromptBuilder.chatSystemPreamble(
            today: today.addingTimeInterval(86_400)
        )
        #expect(laterPreamble != preamble)
        #expect(laterPreamble.contains("Today is 2026-10-15"))
    }

    @Test func chatPreambleRequiresFieldsBeforeAToolCall() {
        #expect(preamble.contains("Gather every value before you call a tool"))
        #expect(preamble.contains("record a workout for me"))
        #expect(preamble.contains("One tool call per reply"))
    }

    @Test func chatPreambleFramesStrengthPlanningAsWeekdaysNotDates() {
        // The strength board is a weekly template; the model must not try to
        // date a strength day the way it dates an aerobic session.
        #expect(preamble.contains("plan_strength_day"))
        #expect(preamble.contains("weekday name, never a date"))
        #expect(preamble.contains("the whole day"))
    }

    @Test func systemTurnCarriesTheAnchorEvenWithoutContext() {
        // The snapshot is attached once per conversation; the date is not, so
        // it has to ride in the system turn to survive later turns.
        let turns = chatTurns(for: request(messages: [
            CoachMessage(role: .user, text: "I ran this morning"),
        ]))
        #expect(turns.first?.text.contains(AICoachPromptBuilder.isoDate(today)) == true)
    }

    @Test func transcriptRoundTripsInOrder() {
        let messages = [
            CoachMessage(role: .user, text: "one"),
            CoachMessage(role: .coach, text: "two"),
            CoachMessage(role: .user, text: "three"),
        ]
        let turns = chatTurns(for: request(messages: messages))
        #expect(turns.dropFirst().map(\.role) == [.user, .coach, .user])
        #expect(turns.dropFirst().map(\.text) == ["one", "two", "three"])
    }

    @Test func contextAttachesToTheFirstUserTurnOnly() {
        let context = sampleContext()
        let snapshot = AICoachPromptBuilder.buildDataSections(for: context)
        let turns = chatTurns(for: request(
            messages: [
                CoachMessage(role: .user, text: "How am I doing?"),
                CoachMessage(role: .coach, text: "Well."),
                CoachMessage(role: .user, text: "And next week?"),
            ],
            context: context
        ))
        let userTurns = turns.filter { $0.role == .user }
        #expect(userTurns[0].text == snapshot + "\nHow am I doing?")
        #expect(userTurns[1].text == "And next week?")
        #expect(!userTurns[1].text.contains("Recent training"))
    }

    @Test func contextPreservesTheOriginalMessageIdentity() {
        // The store keys pending proposals off message ids, so rewriting the
        // first turn's text must not rewrite its id.
        let message = CoachMessage(role: .user, text: "hi")
        let turns = chatTurns(
            for: request(messages: [message], context: sampleContext())
        )
        #expect(turns.last?.id == message.id)
    }

    @Test func noContextMeansNoSnapshotAnywhere() {
        let turns = chatTurns(for: request(messages: [
            CoachMessage(role: .user, text: "How am I doing?")
        ]))
        #expect(turns.allSatisfy { !$0.text.contains("Recent training") })
    }

    @Test func contextRendersMetricAndImperial() {
        for metric in [false, true] {
            let turns = chatTurns(for: request(
                messages: [CoachMessage(role: .user, text: "hi")],
                context: sampleContext(metric: metric)
            ))
            let firstUser = turns.first { $0.role == .user }!
            #expect(firstUser.text.contains(metric ? "km" : "mi"))
        }
    }

    @Test func emptyTranscriptStillYieldsTheSystemTurn() {
        let turns = chatTurns(for: request(messages: []))
        #expect(turns.count == 1)
        #expect(turns[0].role == .system)
    }
}
