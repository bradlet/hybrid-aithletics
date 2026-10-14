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
        #expect(CoachToolSchemas.all.count == CoachTool.allCases.count)
    }

    @Test func schemaNamesMatchToolRawValues() {
        let names = CoachToolSchemas.all.map { fn($0)["name"] as! String }
        #expect(Set(names) == Set(CoachTool.allCases.map(\.rawValue)))
    }

    @Test func chatIsOfferedFirst() {
        // The model should read "just reply" as the default option.
        #expect(fn(CoachToolSchemas.all[0])["name"] as! String == CoachTool.chat.rawValue)
    }

    @Test func everySchemaIsAFunctionEnvelope() {
        for schema in CoachToolSchemas.all {
            #expect(schema["type"] as! String == "function")
            #expect(parameters(schema)["type"] as! String == "object")
            #expect(!(fn(schema)["description"] as! String).isEmpty)
        }
    }

    @Test func everyPropertyIsDescribed() {
        for schema in CoachToolSchemas.all {
            for (name, property) in properties(schema) {
                let property = property as! [String: any Sendable]
                let description = property["description"] as? String
                #expect(description?.isEmpty == false, "\(name) needs a description")
            }
        }
    }

    @Test func requiredFieldsExistAsProperties() {
        for schema in CoachToolSchemas.all {
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
        #expect(Set(required(CoachToolSchemas.suggestScheduleChange))
            == Set(["date", "kind", "rationale"]))
    }

    @Test func scheduleChangeKindEnumeratesEveryCase() {
        let kind = properties(CoachToolSchemas.suggestScheduleChange)["kind"]
            as! [String: any Sendable]
        #expect(kind["enum"] as! [String] == ScheduleChangeKind.allCases.map(\.rawValue))
    }

    @Test func exerciseTypeEnumeratesEveryCase() {
        for schema in [CoachToolSchemas.suggestScheduleChange, CoachToolSchemas.recordWorkout] {
            let type = properties(schema)["exercise_type"] as! [String: any Sendable]
            #expect(type["enum"] as! [String] == CoachExerciseType.allCases.map(\.rawValue))
        }
    }

    @Test func recordWorkoutRequiresOnlyDateAndType() {
        // Everything else is something the athlete may simply not have said.
        #expect(Set(required(CoachToolSchemas.recordWorkout)) == Set(["date", "exercise_type"]))
    }

    @Test func recordWorkoutKeepsFeelingAndExertionSeparate() {
        let props = properties(CoachToolSchemas.recordWorkout)
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
            arguments: ["date": "2026-04-06", "exercise_type": "Run"]
        )
        guard case .recordWorkout(let proposal) = action else {
            Issue.record("expected a workout proposal")
            return
        }
        #expect(proposal.distanceMiles == nil)
        #expect(proposal.durationSeconds == nil)
        #expect(proposal.perceivedExertion == nil)
        #expect(proposal.feeling == nil)
        #expect(proposal.notes == nil)
    }

    @Test func workoutKeepsFeelingAndExertionIndependent() throws {
        // All four combinations survive decoding without one implying the other.
        let combinations: [(Int?, Int?)] = [(nil, nil), (8, nil), (nil, 2), (8, 2)]
        for (exertion, feeling) in combinations {
            var arguments: [String: Any] = ["date": "2026-04-06", "exercise_type": "Run"]
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
                    arguments: ["date": "2026-04-06", "exercise_type": "Run", key: value]
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

    @Test func actionReportsItsTool() {
        #expect(CoachAction.reply("hi").tool == .chat)
        #expect(CoachAction.recordWorkout(WorkoutProposal(
            date: Date(), exerciseType: .run
        )).tool == .recordWorkout)
        #expect(CoachAction.suggestScheduleChange(ScheduleChangeProposal(
            date: Date(), kind: .remove, rationale: "x"
        )).tool == .suggestScheduleChange)
    }
}

// MARK: - Chat Prompt Tests

struct CoachChatPromptTests {

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
        let turns = AICoachPromptBuilder.buildChatTurns(for: request(messages: [
            CoachMessage(role: .user, text: "hi"),
            CoachMessage(role: .coach, text: "hello"),
            CoachMessage(role: .user, text: "again"),
        ]))
        #expect(turns.first?.role == .system)
        #expect(turns.first?.text == AICoachPromptBuilder.chatSystemPreamble)
        #expect(turns.filter { $0.role == .system }.count == 1)
    }

    @Test func chatPreambleIsNotTheOneShotPreamble() {
        // The one-shot preamble mandates a bullet list; conversation must not.
        #expect(AICoachPromptBuilder.chatSystemPreamble != AICoachPromptBuilder.systemPreamble)
        #expect(!AICoachPromptBuilder.chatSystemPreamble.contains("3–5 bullet points"))
    }

    @Test func chatPreambleStatesTheRatingsAreIndependent() {
        let preamble = AICoachPromptBuilder.chatSystemPreamble
        #expect(preamble.contains("RPE"))
        #expect(preamble.contains("independent"))
        #expect(preamble.contains("either may be missing"))
    }

    @Test func transcriptRoundTripsInOrder() {
        let messages = [
            CoachMessage(role: .user, text: "one"),
            CoachMessage(role: .coach, text: "two"),
            CoachMessage(role: .user, text: "three"),
        ]
        let turns = AICoachPromptBuilder.buildChatTurns(for: request(messages: messages))
        #expect(turns.dropFirst().map(\.role) == [.user, .coach, .user])
        #expect(turns.dropFirst().map(\.text) == ["one", "two", "three"])
    }

    @Test func contextAttachesToTheFirstUserTurnOnly() {
        let context = sampleContext()
        let snapshot = AICoachPromptBuilder.buildDataSections(for: context)
        let turns = AICoachPromptBuilder.buildChatTurns(for: request(
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
        let turns = AICoachPromptBuilder.buildChatTurns(
            for: request(messages: [message], context: sampleContext())
        )
        #expect(turns.last?.id == message.id)
    }

    @Test func noContextMeansNoSnapshotAnywhere() {
        let turns = AICoachPromptBuilder.buildChatTurns(for: request(messages: [
            CoachMessage(role: .user, text: "How am I doing?")
        ]))
        #expect(turns.allSatisfy { !$0.text.contains("Recent training") })
    }

    @Test func contextRendersMetricAndImperial() {
        for metric in [false, true] {
            let turns = AICoachPromptBuilder.buildChatTurns(for: request(
                messages: [CoachMessage(role: .user, text: "hi")],
                context: sampleContext(metric: metric)
            ))
            let firstUser = turns.first { $0.role == .user }!
            #expect(firstUser.text.contains(metric ? "km" : "mi"))
        }
    }

    @Test func emptyTranscriptStillYieldsTheSystemTurn() {
        let turns = AICoachPromptBuilder.buildChatTurns(for: request(messages: []))
        #expect(turns.count == 1)
        #expect(turns[0].role == .system)
    }
}
