//
//  AICoachPromptBuilder.swift
//  AICoachCore
//
//  Pure functions that turn a CoachingRequest into the prompt text sent to
//  the on-device LLM. Kept as a non-actor namespace enum so it is trivial
//  to test without touching any runtime state.
//

import Foundation

/// Stateless helpers for building the prompt passed to the AI coach.
public enum AICoachPromptBuilder {

    /// Date formatter used for workout/exercise line prefixes. Cached per
    /// project convention (never allocate in computed properties).
    private static let lineDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd EEE" // e.g. "2026-04-06 Mon"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// System preamble that establishes the coach persona and response style.
    ///
    /// Structured as explicit rules with a bullet-point output format to help
    /// the 4B model stay focused and avoid degenerate looping.
    public static let systemPreamble: String = """
    You are an experienced competitive running coach. Review the athlete's \
    recent training and upcoming plan, then give concrete, conservative \
    suggestions for adaptations — adjusting workout type, duration, distance, \
    intensity, or adding/removing sessions.

    Rules:
    - ONLY reference workouts and sessions listed below.
    - Weigh the athlete's perceived exertion (RPE, 1–10) and how they felt \
    (very weak → very strong) when assessing load. Either may be missing.
    - Respond with 3–5 bullet points. Each bullet is one specific suggestion.
    - Keep the total response under 200 words. Do not repeat yourself.
    """

    /// Formats a date as the model should both read and emit it.
    private static let isoDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// Formats a date with its weekday spelled out, for the "today is" anchor.
    private static let anchorDateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd EEEE"
        f.locale = Locale(identifier: "en_US_POSIX")
        return f
    }()

    /// `YYYY-MM-DD` rendering of a date, matching what `CoachToolDecoder` parses.
    ///
    /// - Parameter date: The date to format.
    /// - Returns: e.g. `"2026-10-14"`.
    public static func isoDate(_ date: Date) -> String {
        isoDateFormatter.string(from: date)
    }

    /// The calendar anchor given to the model on every conversational turn.
    ///
    /// A model has no clock: with nothing anchoring "today" it fills a tool
    /// call's `date` from whatever date it last saw — in practice the example
    /// date out of a tool description — so every recorded workout landed
    /// months away. Stating today, yesterday and the coming week explicitly,
    /// and in the exact format the decoder parses, is what makes "I ran this
    /// morning" resolvable.
    ///
    /// - Parameters:
    ///   - today: The current date.
    ///   - calendar: Calendar used for the relative days. Defaults to `.current`.
    /// - Returns: One sentence naming today, yesterday and tomorrow.
    public static func dateAnchor(today: Date, calendar: Calendar = .current) -> String {
        let startOfToday = calendar.startOfDay(for: today)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: startOfToday) ?? startOfToday
        return """
        Today is \(anchorDateFormatter.string(from: startOfToday)). \
        Yesterday was \(anchorDateFormatter.string(from: yesterday)) and \
        tomorrow is \(anchorDateFormatter.string(from: tomorrow)).
        """
    }

    /// System preamble for tool-enabled conversation.
    ///
    /// Deliberately not a reuse of `systemPreamble`: that one mandates "3–5
    /// bullet points, under 200 words", which is wrong for a back-and-forth and
    /// wrong for tool selection. This keeps the persona and the two load-reading
    /// rules, and adds the guidance a small model needs to not reach for a tool
    /// on every turn.
    ///
    /// Takes `today` rather than reading the clock so the anchor is testable and
    /// so it is recomputed per turn — a conversation left open overnight would
    /// otherwise keep resolving "today" to the day it started.
    ///
    /// - Parameters:
    ///   - today: The current date, used for the calendar anchor.
    ///   - calendar: Calendar used for the relative days. Defaults to `.current`.
    /// - Returns: The system turn text for a conversational request.
    public static func chatSystemPreamble(
        today: Date,
        calendar: Calendar = .current
    ) -> String {
        let startOfToday = calendar.startOfDay(for: today)
        let yesterday = calendar.date(byAdding: .day, value: -1, to: startOfToday) ?? startOfToday
        return """
        You are an experienced competitive running coach talking with your athlete.

        \(dateAnchor(today: today, calendar: calendar))

        Rules:
        - ONLY reference workouts and sessions listed in the conversation.
        - Perceived exertion (RPE, 1–10) measures how hard a session was. Feeling \
        (1–5, very weak → very strong) measures how strong the athlete felt. They \
        are independent, either may be missing, and neither implies the other.
        - Answer conversationally and briefly — a few sentences unless asked for more.
        - Use the chat tool for ordinary replies. Only propose a schedule change when \
        the athlete asks about changing their plan, and only record a workout when \
        they tell you they did one.
        - Only plan strength work when the athlete asks for it. One \
        plan_strength_day call carries the whole day; never split a day across \
        several calls. It also handles adding one or two exercises to a day — \
        it appends, never replaces. To remove, reschedule, offload, or bring \
        back one exercise already on the board, use update_strength_exercise \
        with the weekday and exercise name exactly as listed. The strength \
        board is a weekly template, so both tools take weekday names, never \
        dates.
        - Never invent a date, a distance, or a rating the athlete did not give you.
        - Every date you emit is an absolute YYYY-MM-DD date worked out from today's \
        date above: "today" is \(isoDate(startOfToday)), "yesterday" is \
        \(isoDate(yesterday)), and a weekday name means the nearest such day in the \
        direction the athlete is talking about. Never copy a date out of a tool \
        description or an example.
        - Gather every value before you call a tool. record_workout needs the date, \
        the activity type, and the distance or the duration; suggest_schedule_change \
        needs the date of a session in the plan. If the athlete has not told you one \
        of those — "can you record a workout for me" tells you none of them — answer \
        with the chat tool and ask for what is missing. Never fill a tool argument \
        with a guess.
        - One tool call per reply. Once you have called a tool, stop — do not call it \
        again or correct it with a second call.
        """
    }

    /// Builds the full prompt string for the given request.
    ///
    /// Concatenates the system preamble and user content into a single string.
    /// Prefer using `systemPreamble` and `buildUserContent(for:)` separately
    /// when the model runtime supports distinct system/user message roles.
    ///
    /// - Parameter request: The coaching request to serialize.
    /// - Returns: A prompt ready to be tokenized by the underlying model.
    public static func buildPrompt(for request: CoachingRequest) -> String {
        systemPreamble + "\n\n" + buildUserContent(for: request)
    }

    /// Builds only the user-facing content (workout data + closing question),
    /// without the system preamble.
    ///
    /// Use this alongside `systemPreamble` when the model runtime supports
    /// separate system and user message roles (e.g. `UserInput(chat:)`).
    ///
    /// - Parameter request: The coaching request to serialize.
    /// - Returns: The user content portion of the prompt.
    public static func buildUserContent(for request: CoachingRequest) -> String {
        buildDataSections(for: request) + "\n" + closingQuestion
    }

    /// The closing question appended to the one-shot analysis prompt.
    ///
    /// Kept separate from `buildDataSections(for:)` so conversational prompts
    /// can reuse the training data without inheriting a question the athlete
    /// did not ask.
    public static let closingQuestion: String =
        "Based on how the athlete has been handling their training load, " +
        "what should change about the upcoming plan?"

    /// Serializes just the athlete's training data — recent workouts and the
    /// upcoming plan — with no trailing question.
    ///
    /// This is the shared half of the prompt: `buildUserContent(for:)` appends
    /// `closingQuestion` to it for one-shot analysis, and `buildChatTurns(for:)`
    /// prepends it to the athlete's first message for conversation.
    ///
    /// - Parameter request: The coaching request to serialize.
    /// - Returns: The training-data block, newline separated, ending in a blank line.
    public static func buildDataSections(for request: CoachingRequest) -> String {
        var sections: [String] = []

        sections.append("Recent training (\(request.recentWorkouts.count) workouts):")
        if request.recentWorkouts.isEmpty {
            sections.append("- (no workouts recorded in the lookback window)")
        } else {
            for workout in request.recentWorkouts {
                sections.append(workoutLine(workout, metric: request.useMetricUnits))
            }
        }
        sections.append("")

        sections.append("Upcoming plan (\(request.upcomingExercises.count) scheduled):")
        if request.upcomingExercises.isEmpty {
            sections.append("- (no upcoming exercises scheduled)")
        } else {
            for exercise in request.upcomingExercises {
                sections.append(exerciseLine(exercise, metric: request.useMetricUnits))
            }
        }
        sections.append("")

        // Active lanes only: an offloaded exercise is deliberately out of the
        // week's plan, so showing it as planned would invite the coach to
        // program around work the athlete has set aside.
        let activeStrength = request.strengthExercises
            .filter { !$0.isOffloaded }
            .sorted { $0.weekdayIndex < $1.weekdayIndex }
        sections.append("Strength board (weekly plan, \(activeStrength.count) exercises):")
        if activeStrength.isEmpty {
            sections.append("- (no strength exercises planned)")
        } else {
            for exercise in activeStrength {
                sections.append(strengthLine(exercise))
            }
        }
        sections.append("")

        return sections.joined(separator: "\n")
    }

    // MARK: - Conversation

    /// Assembles the turn sequence sent to the model for a conversation.
    ///
    /// The returned array always begins with a `.system` turn carrying
    /// `chatSystemPreamble(today:)`. When `request.context` is non-nil the
    /// athlete's training snapshot is prepended to the **first** user turn —
    /// once per conversation, rather than on every turn, so the transcript
    /// rather than repeated data fills the context window.
    ///
    /// The calendar anchor rides in the system turn instead, so it is present on
    /// every turn even though the training snapshot is not.
    ///
    /// - Parameters:
    ///   - request: The conversation and its optional training context.
    ///   - today: The current date, for the calendar anchor. Defaults to now.
    ///   - calendar: Calendar used for the relative days. Defaults to `.current`.
    /// - Returns: System turn followed by the conversation, oldest first.
    public static func buildChatTurns(
        for request: CoachChatRequest,
        today: Date = Date(),
        calendar: Calendar = .current
    ) -> [CoachMessage] {
        var turns: [CoachMessage] = [
            CoachMessage(
                role: .system,
                text: chatSystemPreamble(today: today, calendar: calendar)
            )
        ]

        guard let context = request.context else {
            turns.append(contentsOf: request.messages)
            return turns
        }

        let snapshot = buildDataSections(for: context)
        var attached = false
        for message in request.messages {
            guard !attached, message.role == .user else {
                turns.append(message)
                continue
            }
            turns.append(
                CoachMessage(
                    id: message.id,
                    role: .user,
                    text: snapshot + "\n" + message.text
                )
            )
            attached = true
        }
        return turns
    }

    // MARK: - Line formatters

    /// Formats a single completed workout as one prompt line.
    ///
    /// Perceived exertion and feeling are independent signals recorded by the
    /// athlete; each is emitted verbatim and omitted entirely when unrecorded.
    public static func workoutLine(_ workout: CoachWorkout, metric: Bool) -> String {
        let date = lineDateFormatter.string(from: workout.date)
        let distance = workout.distanceMiles.formattedDistance(metric: metric)
        let duration = workout.durationSeconds.formattedDuration
        var line = "- \(date) \(workout.type.rawValue), \(distance), \(duration)"
        if let exertion = workout.perceivedExertion {
            line += ", RPE \(exertion)/10"
        }
        if let feeling = workout.feeling {
            line += ", felt \(feelingDescriptor(feeling))"
        }
        let trimmedNotes = workout.notes.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedNotes.isEmpty {
            line += " — \"\(trimmedNotes)\""
        }
        return line
    }

    /// Lower-cased plain-English descriptor for a 1–5 feeling level, clamped
    /// into range. Deliberately duplicated from the app's `FeelingVisuals`
    /// (different casing, and AICoachCore cannot import app code).
    /// - Parameter feeling: Feeling level. Values outside `1...5` are clamped.
    public static func feelingDescriptor(_ feeling: Int) -> String {
        switch min(max(feeling, 1), 5) {
        case 1:  return "very weak"
        case 2:  return "weak"
        case 3:  return "normal"
        case 4:  return "strong"
        default: return "very strong"
        }
    }

    /// Formats a single planned exercise as one prompt line.
    public static func exerciseLine(_ exercise: CoachExercise, metric: Bool) -> String {
        let date = lineDateFormatter.string(from: exercise.scheduledDate)
        let distance = exercise.distanceMiles.formattedDistance(metric: metric)
        let duration = exercise.durationSeconds.formattedDuration
        return "- \(date) \(exercise.type.rawValue), \(distance), \(duration)"
    }

    /// Formats a single strength-board exercise as one prompt line, e.g.
    /// `- Friday: Barbell Bench Press (Chest), 3×8`. The plan badge appears
    /// only when both sets and reps are set, mirroring
    /// `StrengthExercise.plannedSummary`.
    public static func strengthLine(_ exercise: CoachStrengthExercise) -> String {
        var line = "- \(weekdayName(exercise.weekdayIndex)): \(exercise.name) (\(exercise.muscleGroup))"
        if let sets = exercise.plannedSets, let reps = exercise.plannedReps {
            line += ", \(sets)×\(reps)"
        }
        return line
    }

    /// The day name for a lane index, tolerating an out-of-range value from
    /// synced data rather than trapping.
    private static func weekdayName(_ weekdayIndex: Int) -> String {
        let names = StrengthDayProposal.weekdayNames
        guard names.indices.contains(weekdayIndex) else { return "Day \(weekdayIndex)" }
        return names[weekdayIndex]
    }
}
