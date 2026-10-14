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
        return WorkoutProposal(
            date: try requiredDate("date", in: arguments),
            exerciseType: type,
            distanceMiles: try optionalDistance("distance_miles", in: arguments),
            durationSeconds: try optionalDuration("duration_seconds", in: arguments),
            perceivedExertion: try optionalRating(
                "perceived_exertion", in: arguments, range: 1...10
            ),
            feeling: try optionalRating("feeling", in: arguments, range: 1...5),
            notes: optionalString("notes", in: arguments)
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

    /// Reads a subjective rating, rejecting out-of-range values rather than
    /// clamping them — a model that says "RPE 15" has misunderstood the scale,
    /// and silently storing 10 would put a number the athlete never gave into
    /// their training history.
    private static func optionalRating(
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
