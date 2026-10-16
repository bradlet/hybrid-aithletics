//
//  CoachToolDecoding.swift
//  AICoachCore
//
//  Turns a raw model tool call — a function name plus a JSON argument object —
//  into a validated `CoachAction`.
//
//  This is deliberately NOT done through the model runtime's own
//  `ToolCall.execute(with:)`: that helper constructs a default `JSONDecoder`,
//  whose date strategy expects a number of seconds since 2001, so a
//  model-emitted "2026-04-06" fails to decode. Validation also belongs
//  somewhere pure and testable — a 4B model will emit out-of-range ratings and
//  dates that aren't dates, and each of those should become a visible rejection
//  rather than a decode crash or a silently clamped value.
//

import Foundation

/// Why a tool call could not be turned into an action.
public enum CoachToolDecodeError: Error, Equatable, LocalizedError {
    /// The function name matched no known tool.
    case unknownTool(String)
    /// A required argument was absent.
    case missingArgument(String)
    /// An argument was present but unusable.
    case invalidArgument(name: String, reason: String)

    public var errorDescription: String? {
        switch self {
        case .unknownTool(let name):
            return "The coach asked for an unknown tool \"\(name)\"."
        case .missingArgument(let name):
            return "The coach left out a required value (\(name))."
        case .invalidArgument(let name, let reason):
            return "The coach sent an unusable value for \(name): \(reason)."
        }
    }
}

/// Decodes and validates raw model tool calls.
public enum CoachToolDecoder {

    /// Parses the `YYYY-MM-DD` dates the tool schemas ask the model for.
    /// Cached per project convention.
    private static let dateFormatter: DateFormatter = {
        let f = DateFormatter()
        f.dateFormat = "yyyy-MM-dd"
        f.locale = Locale(identifier: "en_US_POSIX")
        f.timeZone = TimeZone.current
        return f
    }()

    /// Decodes a tool call into an action.
    ///
    /// - Parameters:
    ///   - name: The function name the model emitted.
    ///   - arguments: The decoded JSON argument object. Values are the loose
    ///     types a JSON parse produces (`String`, `Double`, `Int`, `Bool`).
    /// - Returns: The validated action.
    /// - Throws: `CoachToolDecodeError` when the call cannot be used.
    public static func decode(
        name: String,
        arguments: [String: Any]
    ) throws -> CoachAction {
        guard let tool = CoachTool(rawValue: name) else {
            throw CoachToolDecodeError.unknownTool(name)
        }
        switch tool {
        case .chat:
            return .reply(try requiredString("message", in: arguments))
        case .suggestScheduleChange:
            return .suggestScheduleChange(try scheduleChange(from: arguments))
        case .recordWorkout:
            return .recordWorkout(try workout(from: arguments))
        case .planStrengthDay:
            return .planStrengthDay(try strengthDay(from: arguments))
        case .updateStrengthExercise:
            return .updateStrengthExercise(try strengthExerciseUpdate(from: arguments))
        }
    }

    // MARK: - Per-tool decoding

    private static func scheduleChange(
        from arguments: [String: Any]
    ) throws -> ScheduleChangeProposal {
        let rawKind = try requiredString("kind", in: arguments)
        guard let kind = ScheduleChangeKind(rawValue: rawKind) else {
            throw CoachToolDecodeError.invalidArgument(
                name: "kind",
                reason: "\"\(rawKind)\" is not a known change"
            )
        }
        let proposal = ScheduleChangeProposal(
            date: try requiredDate("date", in: arguments),
            kind: kind,
            distanceMiles: try optionalDistance("distance_miles", in: arguments),
            durationSeconds: try optionalDuration("duration_seconds", in: arguments),
            exerciseType: try optionalExerciseType("exercise_type", in: arguments),
            rationale: try requiredString("rationale", in: arguments)
        )
        // A change has to actually say what it changes to. Without this a
        // "shorten Tuesday" call with no distance reads as a no-op the athlete
        // would be asked to approve.
        switch kind {
        case .adjustDistance where proposal.distanceMiles == nil:
            throw CoachToolDecodeError.missingArgument("distance_miles")
        case .adjustDuration where proposal.durationSeconds == nil:
            throw CoachToolDecodeError.missingArgument("duration_seconds")
        case .changeType where proposal.exerciseType == nil:
            throw CoachToolDecodeError.missingArgument("exercise_type")
        case .add where proposal.exerciseType == nil:
            throw CoachToolDecodeError.missingArgument("exercise_type")
        default:
            break
        }
        return proposal
    }

    private static func workout(from arguments: [String: Any]) throws -> WorkoutProposal {
        guard let type = try optionalExerciseType("exercise_type", in: arguments) else {
            throw CoachToolDecodeError.missingArgument("exercise_type")
        }
        let proposal = WorkoutProposal(
            date: try requiredDate("date", in: arguments),
            exerciseType: type,
            distanceMiles: try optionalDistance("distance_miles", in: arguments),
            durationSeconds: try optionalDuration("duration_seconds", in: arguments),
            perceivedExertion: try optionalBoundedInteger(
                "perceived_exertion", in: arguments, range: 1...10
            ),
            feeling: try optionalBoundedInteger("feeling", in: arguments, range: 1...5),
            notes: optionalString("notes", in: arguments)
        )
        // A workout the athlete has not sized is not a workout they described.
        // Without this, "can you record a workout for me" is enough for the
        // model to call the tool, and the athlete is handed a pre-filled sheet
        // built from a date it guessed. Rejecting sends the turn back to chat,
        // where the coach asks what they actually did.
        guard proposal.distanceMiles != nil || proposal.durationSeconds != nil else {
            throw CoachToolDecodeError.missingArgument("distance_miles or duration_seconds")
        }
        return proposal
    }

    /// Decodes a strength-day proposal: a weekday lane plus the batch of
    /// exercises to fill it with.
    private static func strengthDay(
        from arguments: [String: Any]
    ) throws -> StrengthDayProposal {
        StrengthDayProposal(
            weekdayIndex: try requiredWeekday("weekday", in: arguments),
            exercises: try strengthDayExercises(from: arguments),
            rationale: try requiredString("rationale", in: arguments)
        )
    }

    /// Reads the `exercises` argument in either shape it can arrive in. The
    /// schema declares the flat line-format string — the only nested-free
    /// representation the model runtime's Gemma dialect parser survives — but
    /// a model that emits real-JSON nested arrays anyway still decodes.
    private static func strengthDayExercises(
        from arguments: [String: Any]
    ) throws -> [PlannedStrengthExercise] {
        if let rawExercises = arguments["exercises"] as? [[String: Any]] {
            guard !rawExercises.isEmpty else {
                throw CoachToolDecodeError.invalidArgument(
                    name: "exercises",
                    reason: "a strength day needs at least one exercise"
                )
            }
            guard rawExercises.count <= StrengthDayProposal.maxExercises else {
                throw CoachToolDecodeError.invalidArgument(
                    name: "exercises",
                    reason: "\(rawExercises.count) exercises is more than one day holds (max \(StrengthDayProposal.maxExercises))"
                )
            }
            return try rawExercises.map(plannedStrengthExercise(from:))
        }
        guard let text = optionalString("exercises", in: arguments) else {
            throw CoachToolDecodeError.missingArgument("exercises")
        }
        return try parseStrengthExerciseList(text)
    }

    /// Parses the line-format exercise list the schema asks for:
    /// `Name (Muscle Group), sets x reps`, entries separated by semicolons or
    /// newlines — the same shape the prompt uses to list the strength board.
    private static func parseStrengthExerciseList(
        _ text: String
    ) throws -> [PlannedStrengthExercise] {
        let entries = text
            .replacingOccurrences(of: "\n", with: ";")
            .components(separatedBy: ";")
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !entries.isEmpty else {
            throw CoachToolDecodeError.invalidArgument(
                name: "exercises",
                reason: "a strength day needs at least one exercise"
            )
        }
        guard entries.count <= StrengthDayProposal.maxExercises else {
            throw CoachToolDecodeError.invalidArgument(
                name: "exercises",
                reason: "\(entries.count) exercises is more than one day holds (max \(StrengthDayProposal.maxExercises))"
            )
        }
        return try entries.map(parseStrengthExerciseLine(_:))
    }

    /// Parses one `Name (Muscle Group), NxM` entry.
    ///
    /// The muscle group is read from the LAST parenthesized span, so a name
    /// carrying its own qualifier — "Pull-Up (Assisted) (Back)" — still
    /// resolves its group correctly.
    private static func parseStrengthExerciseLine(
        _ entry: String
    ) throws -> PlannedStrengthExercise {
        guard let open = entry.lastIndex(of: "("),
              let close = entry[open...].firstIndex(of: ")"),
              close > open
        else {
            throw CoachToolDecodeError.invalidArgument(
                name: "exercises",
                reason: "\"\(entry)\" needs its muscle group in parentheses, "
                    + "e.g. \"Barbell Bench Press (Chest), 3x8\""
            )
        }
        let rawGroup = String(entry[entry.index(after: open)..<close])
        guard let group = CoachMuscleGroup.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(rawGroup) == .orderedSame
        }) else {
            throw CoachToolDecodeError.invalidArgument(
                name: "muscle_group",
                reason: "\"\(rawGroup)\" is not a known muscle group"
            )
        }

        let name = String(entry[..<open])
            .trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
            .trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else {
            throw CoachToolDecodeError.invalidArgument(
                name: "exercises",
                reason: "\"\(entry)\" has no exercise name"
            )
        }

        let tail = String(entry[entry.index(after: close)...])
        let (sets, reps) = try parseSetsReps(tail, entry: entry)
        return PlannedStrengthExercise(
            name: name, muscleGroup: group, plannedSets: sets, plannedReps: reps
        )
    }

    /// Reads the optional sets×reps suffix after the muscle-group paren:
    /// empty, or "NxM" with either `x` or `×` (an optional leading comma is
    /// tolerated). One number without the other is malformed, matching the
    /// per-object path's only-together rule; ranges mirror the app's
    /// `StrengthPlanDraft` steppers, as they do in `plannedStrengthExercise`.
    private static func parseSetsReps(
        _ tail: String, entry: String
    ) throws -> (sets: Int?, reps: Int?) {
        var trimmed = tail.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return (nil, nil) }
        if trimmed.hasPrefix(",") {
            trimmed = String(trimmed.dropFirst()).trimmingCharacters(in: .whitespaces)
        }
        let parts = trimmed.lowercased()
            .replacingOccurrences(of: "×", with: "x")
            .components(separatedBy: "x")
            .map { $0.trimmingCharacters(in: .whitespaces) }
        guard parts.count == 2, let sets = Int(parts[0]), let reps = Int(parts[1]) else {
            throw CoachToolDecodeError.invalidArgument(
                name: "exercises",
                reason: "\"\(entry)\" — sets and reps read as \"NxM\", e.g. \", 3x8\""
            )
        }
        guard (1...20).contains(sets), (1...100).contains(reps) else {
            throw CoachToolDecodeError.invalidArgument(
                name: "exercises",
                reason: "\"\(entry)\" — sets must be 1–20 and reps 1–100"
            )
        }
        return (sets, reps)
    }

    /// Decodes a strength-exercise update: one board exercise plus the change
    /// to make to it.
    private static func strengthExerciseUpdate(
        from arguments: [String: Any]
    ) throws -> StrengthExerciseUpdateProposal {
        let rawKind = try requiredString("change", in: arguments)
        guard let kind = StrengthExerciseChangeKind(rawValue: rawKind) else {
            throw CoachToolDecodeError.invalidArgument(
                name: "change",
                reason: "\"\(rawKind)\" is not a known change"
            )
        }
        let proposal = StrengthExerciseUpdateProposal(
            weekdayIndex: try requiredWeekday("weekday", in: arguments),
            exerciseName: try requiredString("exercise", in: arguments),
            kind: kind,
            newWeekdayIndex: try optionalWeekday("new_weekday", in: arguments),
            rationale: try requiredString("rationale", in: arguments)
        )
        // A move has to actually say where to. Without this a "move bench
        // press to Saturday" call with no new_weekday is a no-op the athlete
        // would be asked to approve — same rule as the schedule-change values.
        if kind == .moveToDay {
            guard let destination = proposal.newWeekdayIndex else {
                throw CoachToolDecodeError.missingArgument("new_weekday")
            }
            guard destination != proposal.weekdayIndex else {
                throw CoachToolDecodeError.invalidArgument(
                    name: "new_weekday",
                    reason: "the exercise is already in that day's lane"
                )
            }
        }
        return proposal
    }

    /// Decodes one entry of a strength-day proposal.
    private static func plannedStrengthExercise(
        from arguments: [String: Any]
    ) throws -> PlannedStrengthExercise {
        let rawGroup = try requiredString("muscle_group", in: arguments)
        guard let group = CoachMuscleGroup.allCases.first(where: {
            $0.rawValue.caseInsensitiveCompare(rawGroup) == .orderedSame
        }) else {
            throw CoachToolDecodeError.invalidArgument(
                name: "muscle_group",
                reason: "\"\(rawGroup)\" is not a known muscle group"
            )
        }
        // Ranges mirror the app's `StrengthPlanDraft` steppers (AICoachCore
        // cannot import app code — same deliberate duplication as
        // `feelingDescriptor`). A plan exists only when both are set, so one
        // without the other is a mistake worth sending back.
        let sets = try optionalBoundedInteger("sets", in: arguments, range: 1...20)
        let reps = try optionalBoundedInteger("reps", in: arguments, range: 1...100)
        if (sets == nil) != (reps == nil) {
            throw CoachToolDecodeError.missingArgument(sets == nil ? "sets" : "reps")
        }
        return PlannedStrengthExercise(
            name: try requiredString("name", in: arguments),
            muscleGroup: group,
            plannedSets: sets,
            plannedReps: reps
        )
    }

    // MARK: - Field readers

    private static func requiredString(
        _ key: String,
        in arguments: [String: Any]
    ) throws -> String {
        guard let value = optionalString(key, in: arguments) else {
            throw CoachToolDecodeError.missingArgument(key)
        }
        return value
    }

    /// Reads a non-empty string, treating whitespace-only as absent.
    private static func optionalString(
        _ key: String,
        in arguments: [String: Any]
    ) -> String? {
        guard let raw = arguments[key] as? String else { return nil }
        let trimmed = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    private static func requiredDate(
        _ key: String,
        in arguments: [String: Any]
    ) throws -> Date {
        let raw = try requiredString(key, in: arguments)
        guard let date = dateFormatter.date(from: raw) else {
            throw CoachToolDecodeError.invalidArgument(
                name: key,
                reason: "\"\(raw)\" is not a YYYY-MM-DD date"
            )
        }
        return date
    }

    private static func requiredWeekday(
        _ key: String,
        in arguments: [String: Any]
    ) throws -> Int {
        guard let index = try optionalWeekday(key, in: arguments) else {
            throw CoachToolDecodeError.missingArgument(key)
        }
        return index
    }

    /// Reads a weekday name into its lane index, case-insensitively — the
    /// board is a weekly template, so "friday" and "Friday" both mean lane 5.
    private static func optionalWeekday(
        _ key: String,
        in arguments: [String: Any]
    ) throws -> Int? {
        guard let raw = optionalString(key, in: arguments) else { return nil }
        guard let index = StrengthDayProposal.weekdayNames.firstIndex(where: {
            $0.caseInsensitiveCompare(raw) == .orderedSame
        }) else {
            throw CoachToolDecodeError.invalidArgument(
                name: key,
                reason: "\"\(raw)\" is not a day of the week"
            )
        }
        return index
    }

    /// Reads a number that may arrive as `Double`, `Int`, or a numeric string.
    private static func optionalNumber(
        _ key: String,
        in arguments: [String: Any]
    ) -> Double? {
        switch arguments[key] {
        case let value as Double: return value
        case let value as Int: return Double(value)
        case let value as String: return Double(value)
        default: return nil
        }
    }

    private static func optionalDistance(
        _ key: String,
        in arguments: [String: Any]
    ) throws -> Double? {
        guard let value = optionalNumber(key, in: arguments) else { return nil }
        guard value.isFinite, value >= 0 else {
            throw CoachToolDecodeError.invalidArgument(
                name: key,
                reason: "\(value) is not a usable distance"
            )
        }
        return value
    }

    private static func optionalDuration(
        _ key: String,
        in arguments: [String: Any]
    ) throws -> Int? {
        guard let value = optionalNumber(key, in: arguments) else { return nil }
        guard value.isFinite, value >= 0, value <= Double(Int.max) else {
            throw CoachToolDecodeError.invalidArgument(
                name: key,
                reason: "\(value) is not a usable duration"
            )
        }
        return Int(value)
    }

    /// Reads a bounded whole number, rejecting out-of-range values rather
    /// than clamping them — a model that says "RPE 15" or "400 sets" has
    /// misunderstood the scale, and silently storing the nearest bound would
    /// put a number the athlete never gave into their plan or history.
    private static func optionalBoundedInteger(
        _ key: String,
        in arguments: [String: Any],
        range: ClosedRange<Int>
    ) throws -> Int? {
        guard let value = optionalNumber(key, in: arguments) else { return nil }
        guard value.isFinite, value == value.rounded(), range.contains(Int(value)) else {
            throw CoachToolDecodeError.invalidArgument(
                name: key,
                reason: "\(value) is outside \(range.lowerBound)–\(range.upperBound)"
            )
        }
        return Int(value)
    }

    private static func optionalExerciseType(
        _ key: String,
        in arguments: [String: Any]
    ) throws -> CoachExerciseType? {
        guard let raw = optionalString(key, in: arguments) else { return nil }
        guard let type = CoachExerciseType(rawValue: raw) else {
            throw CoachToolDecodeError.invalidArgument(
                name: key,
                reason: "\"\(raw)\" is not a known exercise type"
            )
        }
        return type
    }
}
