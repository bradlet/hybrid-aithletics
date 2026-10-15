//
//  CoachToolSchemas.swift
//  AICoachCore
//
//  JSON Schema definitions for the coach's tools, as plain dictionaries.
//
//  These match the `ToolSpec` shape the model runtime expects
//  (`[String: any Sendable]`) but deliberately carry no MLX import: AICoachCore
//  stays runtime-agnostic so the eval CLI can score tool selection without the
//  app, and the app passes these straight through to generation.
//

import Foundation

/// JSON Schema definitions for every tool the coach may call.
public enum CoachToolSchemas {

    /// All tool schemas, in the order they are presented to the model.
    ///
    /// `chat` comes first so the model's default reading is "just reply".
    ///
    /// - Parameter today: The current date, named in every date argument's
    ///   description so the model has an anchor at the point it fills the
    ///   field in. A fixed example date here instead is what a model copies
    ///   into the call verbatim.
    /// - Returns: Tool schemas in presentation order.
    public static func all(today: Date) -> [[String: any Sendable]] {
        [chat, suggestScheduleChange(today: today), recordWorkout(today: today)]
    }

    /// Date format the model is told to emit, and that `CoachToolDecoder` parses.
    ///
    /// Carries today's date rather than a static example: the example date this
    /// once held ("e.g. 2026-04-06") was being emitted as the workout date
    /// regardless of when the athlete actually trained.
    /// - Parameter today: The current date.
    /// - Returns: A description of the expected date format.
    public static func dateFormatDescription(today: Date) -> String {
        "an absolute calendar date as YYYY-MM-DD, where today is "
            + AICoachPromptBuilder.isoDate(today)
    }

    // MARK: - chat

    /// Reply conversationally, with no side effect.
    public static var chat: [String: any Sendable] {
        function(
            name: CoachTool.chat.rawValue,
            description: """
            Reply to the athlete in conversation. Use this for questions, \
            explanations, encouragement, and anything that does not change \
            their training log or plan. This is the default.
            """,
            properties: [
                "message": string("Your reply to the athlete.")
            ],
            required: ["message"]
        )
    }

    // MARK: - suggest_schedule_change

    /// Propose an edit to one scheduled session.
    public static func suggestScheduleChange(today: Date) -> [String: any Sendable] {
        function(
            name: CoachTool.suggestScheduleChange.rawValue,
            description: """
            Propose a change to ONE scheduled session in the athlete's upcoming \
            plan. Only use a date that appears in the upcoming plan, except for \
            kind "add". The athlete reviews and confirms every proposal, so \
            explain your reasoning in "rationale".
            """,
            properties: [
                "date": string("Which session to change — \(dateFormatDescription(today: today))."),
                "kind": enumeration(
                    ScheduleChangeKind.allCases.map(\.rawValue),
                    "What to change about the session."
                ),
                "distance_miles": number("New target distance in miles. Required for adjust_distance."),
                "duration_seconds": integer("New target duration in seconds. Required for adjust_duration."),
                "exercise_type": enumeration(
                    CoachExerciseType.allCases.map(\.rawValue),
                    "New activity type. Required for change_type."
                ),
                "rationale": string("One or two sentences on why this change helps."),
            ],
            required: ["date", "kind", "rationale"]
        )
    }

    // MARK: - record_workout

    /// Propose recording a workout the athlete described.
    public static func recordWorkout(today: Date) -> [String: any Sendable] {
        function(
            name: CoachTool.recordWorkout.rawValue,
            description: """
            Propose recording a workout the athlete just told you they did. The \
            athlete reviews and confirms before anything is saved. Only fill in \
            fields they actually stated — omit the rest rather than guessing.

            Call this only once the athlete has told you when they trained, what \
            they did, and how far or how long. If any of those is still missing — \
            "can you record a workout for me" gives you none of them — use the \
            chat tool to ask instead of calling this with a guess.
            """,
            properties: [
                "date": string("The day performed — \(dateFormatDescription(today: today))."),
                "exercise_type": enumeration(
                    CoachExerciseType.allCases.map(\.rawValue),
                    "The activity type."
                ),
                "distance_miles": number("Distance covered in miles. Omit if not stated."),
                "duration_seconds": integer("Duration in seconds. Omit if not stated."),
                "perceived_exertion": integer("""
                How HARD the session was: RPE from 1 (very easy) to 10 (maximum \
                effort). Omit entirely if the athlete did not say how hard it was. \
                This is separate from how they felt.
                """),
                "feeling": integer("""
                How STRONG the athlete felt: 1 (very weak) to 5 (very strong). \
                Omit entirely if they did not say how they felt. This is separate \
                from how hard the session was — do not derive one from the other.
                """),
                "notes": string("Anything else the athlete mentioned. Omit if nothing."),
            ],
            required: ["date", "exercise_type"]
        )
    }

    // MARK: - Schema builders

    /// Wraps a function definition in the tool envelope.
    private static func function(
        name: String,
        description: String,
        properties: [String: any Sendable],
        required: [String]
    ) -> [String: any Sendable] {
        [
            "type": "function",
            "function": [
                "name": name,
                "description": description,
                "parameters": [
                    "type": "object",
                    "properties": properties,
                    "required": required,
                ] as [String: any Sendable],
            ] as [String: any Sendable],
        ]
    }

    private static func string(_ description: String) -> [String: any Sendable] {
        ["type": "string", "description": description]
    }

    private static func number(_ description: String) -> [String: any Sendable] {
        ["type": "number", "description": description]
    }

    private static func integer(_ description: String) -> [String: any Sendable] {
        ["type": "integer", "description": description]
    }

    private static func enumeration(
        _ cases: [String],
        _ description: String
    ) -> [String: any Sendable] {
        ["type": "string", "enum": cases, "description": description]
    }
}
