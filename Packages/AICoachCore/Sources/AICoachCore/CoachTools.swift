//
//  CoachTools.swift
//  AICoachCore
//
//  The coach's tool vocabulary: what it may ask the app to do, and the
//  argument payloads for each. These types are both the decode targets for a
//  model tool call and the source of truth for the JSON schemas in
//  `CoachToolSchemas`.
//
//  The mutating tools describe *proposals*, not completed writes. The app
//  surfaces each one for the athlete to accept or dismiss — a 4B model editing
//  a training log unattended is not a recoverable failure.
//

import Foundation

/// A tool the coach may invoke. Raw values are the schema function names.
public enum CoachTool: String, Codable, CaseIterable, Sendable {
    /// Reply conversationally. Matches the coach's pre-tool behavior.
    case chat
    /// Propose a change to a scheduled session.
    case suggestScheduleChange = "suggest_schedule_change"
    /// Propose recording a workout the athlete described.
    case recordWorkout = "record_workout"
    /// Propose a batch of strength exercises for one weekday's lane.
    case planStrengthDay = "plan_strength_day"
    /// Propose a change to one strength exercise already on the board.
    case updateStrengthExercise = "update_strength_exercise"
}

/// A decoded, validated tool call — what the app acts on.
public enum CoachAction: Equatable, Sendable {
    /// Conversational text with no side effect.
    case reply(String)
    /// A proposed edit to the upcoming plan, pending the athlete's acceptance.
    case suggestScheduleChange(ScheduleChangeProposal)
    /// A proposed workout record, pending the athlete's acceptance.
    case recordWorkout(WorkoutProposal)
    /// A proposed strength day, pending the athlete's acceptance.
    case planStrengthDay(StrengthDayProposal)
    /// A proposed edit to one board exercise, pending the athlete's acceptance.
    case updateStrengthExercise(StrengthExerciseUpdateProposal)

    /// Which tool produced this action.
    public var tool: CoachTool {
        switch self {
        case .reply: .chat
        case .suggestScheduleChange: .suggestScheduleChange
        case .recordWorkout: .recordWorkout
        case .planStrengthDay: .planStrengthDay
        case .updateStrengthExercise: .updateStrengthExercise
        }
    }
}

/// What kind of edit a schedule-change proposal describes.
public enum ScheduleChangeKind: String, Codable, CaseIterable, Sendable {
    /// Change the target distance of an existing session.
    case adjustDistance = "adjust_distance"
    /// Change the target duration of an existing session.
    case adjustDuration = "adjust_duration"
    /// Change the activity type of an existing session.
    case changeType = "change_type"
    /// Drop an existing session.
    case remove
    /// Add a new session.
    case add
}

/// A proposed change to one scheduled session.
public struct ScheduleChangeProposal: Codable, Equatable, Sendable {
    /// The day of the session to change, or of the session to add.
    public let date: Date
    /// What kind of change this is.
    public let kind: ScheduleChangeKind
    /// New target distance in miles. Applies to `.adjustDistance` and `.add`.
    public let distanceMiles: Double?
    /// New target duration in seconds. Applies to `.adjustDuration` and `.add`.
    public let durationSeconds: Int?
    /// New activity type. Applies to `.changeType` and `.add`.
    public let exerciseType: CoachExerciseType?
    /// The coach's reason, shown to the athlete beside Accept / Dismiss.
    public let rationale: String

    public init(
        date: Date,
        kind: ScheduleChangeKind,
        distanceMiles: Double? = nil,
        durationSeconds: Int? = nil,
        exerciseType: CoachExerciseType? = nil,
        rationale: String
    ) {
        self.date = date
        self.kind = kind
        self.distanceMiles = distanceMiles
        self.durationSeconds = durationSeconds
        self.exerciseType = exerciseType
        self.rationale = rationale
    }
}

/// One exercise in a proposed strength day.
public struct PlannedStrengthExercise: Codable, Equatable, Sendable {
    /// Common exercise name, e.g. "Barbell Bench Press". Matched against the
    /// exercise library app-side; an unmatched name becomes a plain entry.
    public let name: String
    /// Primary muscle group worked.
    public let muscleGroup: CoachMuscleGroup
    /// Planned number of sets, or `nil` when no plan is proposed. A plan
    /// exists only when both this and `plannedReps` are set.
    public let plannedSets: Int?
    /// Planned reps per set, or `nil` when no plan is proposed.
    public let plannedReps: Int?

    public init(
        name: String,
        muscleGroup: CoachMuscleGroup,
        plannedSets: Int? = nil,
        plannedReps: Int? = nil
    ) {
        self.name = name
        self.muscleGroup = muscleGroup
        self.plannedSets = plannedSets
        self.plannedReps = plannedReps
    }
}

/// A proposed strength day: a batch of exercises for one day-of-week lane on
/// the athlete's weekly strength board.
///
/// The board is a weekly template with no dates, so the proposal targets a
/// weekday rather than a calendar date — "set up a full body routine on
/// Friday" means the Friday lane. The whole day rides in one proposal so the
/// athlete reviews the routine as a unit.
public struct StrengthDayProposal: Codable, Equatable, Sendable {
    /// Day names in lane order (Sunday=0 ... Saturday=6), matching the app's
    /// `weekdayIndex` convention. Shared by the tool schema (the enum the
    /// model picks from) and the decoder (name → index).
    public static let weekdayNames = [
        "Sunday", "Monday", "Tuesday", "Wednesday", "Thursday", "Friday", "Saturday",
    ]

    /// The most exercises one day proposal may carry.
    public static let maxExercises = 8

    /// The day-of-week lane to fill (Sunday=0 ... Saturday=6).
    public let weekdayIndex: Int
    /// The exercises to add, in board order.
    public let exercises: [PlannedStrengthExercise]
    /// The coach's reason, shown to the athlete beside Accept / Dismiss.
    public let rationale: String

    public init(weekdayIndex: Int, exercises: [PlannedStrengthExercise], rationale: String) {
        self.weekdayIndex = weekdayIndex
        self.exercises = exercises
        self.rationale = rationale
    }

    /// The lane's day name, e.g. "Friday". Falls back to a numbered day for
    /// an out-of-range index rather than trapping on model data.
    public var weekdayName: String {
        guard Self.weekdayNames.indices.contains(weekdayIndex) else {
            return "Day \(weekdayIndex)"
        }
        return Self.weekdayNames[weekdayIndex]
    }
}

/// What kind of edit a strength-exercise update describes. Raw values are the
/// schema's `change` enum.
public enum StrengthExerciseChangeKind: String, Codable, CaseIterable, Sendable {
    /// Drop the exercise from the board entirely, including its lift history.
    case remove
    /// Move the exercise to another day's lane, keeping its section
    /// (active stays active, offloaded stays offloaded).
    case moveToDay = "move_to_day"
    /// Move the exercise out of the active plan into its day's offloaded
    /// section.
    case offload
    /// Bring an offloaded exercise back into its day's active plan.
    case onboard
}

/// A proposed change to one exercise already on the athlete's strength board.
///
/// The exercise is addressed by weekday lane plus name — the same
/// case-insensitive name convention the rest of the strength flow uses —
/// rather than by an identifier the model would have to copy from the prompt.
public struct StrengthExerciseUpdateProposal: Codable, Equatable, Sendable {
    /// The day-of-week lane the exercise currently lives in
    /// (Sunday=0 ... Saturday=6).
    public let weekdayIndex: Int
    /// The exercise's name as it appears on the board.
    public let exerciseName: String
    /// What kind of change this is.
    public let kind: StrengthExerciseChangeKind
    /// The destination lane for `.moveToDay`, otherwise `nil`.
    public let newWeekdayIndex: Int?
    /// The coach's reason, shown to the athlete beside Accept / Dismiss.
    public let rationale: String

    public init(
        weekdayIndex: Int,
        exerciseName: String,
        kind: StrengthExerciseChangeKind,
        newWeekdayIndex: Int? = nil,
        rationale: String
    ) {
        self.weekdayIndex = weekdayIndex
        self.exerciseName = exerciseName
        self.kind = kind
        self.newWeekdayIndex = newWeekdayIndex
        self.rationale = rationale
    }

    /// The current lane's day name, tolerating an out-of-range index.
    public var weekdayName: String {
        Self.weekdayName(weekdayIndex)
    }

    /// The destination lane's day name for a `.moveToDay`, tolerating an
    /// out-of-range index.
    public var newWeekdayName: String? {
        newWeekdayIndex.map(Self.weekdayName(_:))
    }

    private static func weekdayName(_ index: Int) -> String {
        let names = StrengthDayProposal.weekdayNames
        guard names.indices.contains(index) else { return "Day \(index)" }
        return names[index]
    }
}

/// A proposed workout record, assembled from what the athlete described.
///
/// `feeling` and `perceivedExertion` are two independent optionals and must
/// stay that way. They measure different things — how strong the athlete felt
/// versus how hard the session was — and neither is derivable from the other.
/// `nil` means the athlete did not say, which is a correct and common outcome.
public struct WorkoutProposal: Codable, Equatable, Sendable {
    /// The day the workout was performed.
    public let date: Date
    /// The activity type.
    public let exerciseType: CoachExerciseType
    /// Distance covered in miles, or `nil` when not stated.
    public let distanceMiles: Double?
    /// Duration in seconds, or `nil` when not stated.
    public let durationSeconds: Int?
    /// Rate of perceived exertion, 1 (very easy) … 10 (maximum effort).
    /// `nil` when the athlete did not say how hard it was.
    public let perceivedExertion: Int?
    /// How the athlete felt, 1 (very weak) … 5 (very strong).
    /// `nil` when the athlete did not say how they felt.
    public let feeling: Int?
    /// Free-text notes, or `nil` when there are none.
    public let notes: String?

    public init(
        date: Date,
        exerciseType: CoachExerciseType,
        distanceMiles: Double? = nil,
        durationSeconds: Int? = nil,
        perceivedExertion: Int? = nil,
        feeling: Int? = nil,
        notes: String? = nil
    ) {
        self.date = date
        self.exerciseType = exerciseType
        self.distanceMiles = distanceMiles
        self.durationSeconds = durationSeconds
        self.perceivedExertion = perceivedExertion
        self.feeling = feeling
        self.notes = notes
    }
}
