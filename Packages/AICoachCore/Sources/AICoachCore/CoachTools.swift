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
}

/// A decoded, validated tool call — what the app acts on.
public enum CoachAction: Equatable, Sendable {
    /// Conversational text with no side effect.
    case reply(String)
    /// A proposed edit to the upcoming plan, pending the athlete's acceptance.
    case suggestScheduleChange(ScheduleChangeProposal)
    /// A proposed workout record, pending the athlete's acceptance.
    case recordWorkout(WorkoutProposal)

    /// Which tool produced this action.
    public var tool: CoachTool {
        switch self {
        case .reply: .chat
        case .suggestScheduleChange: .suggestScheduleChange
        case .recordWorkout: .recordWorkout
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
