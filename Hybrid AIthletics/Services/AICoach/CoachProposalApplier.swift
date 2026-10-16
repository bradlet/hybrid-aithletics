//
//  CoachProposalApplier.swift
//  Hybrid AIthletics
//
//  Turns an accepted coach proposal into a SwiftData mutation.
//
//  Nothing here runs until the athlete taps Accept. A proposal that cannot be
//  resolved to a real session fails loudly rather than inventing one: the coach
//  naming a day the athlete has nothing scheduled on is a model mistake, and
//  silently creating a session would put work in the plan nobody asked for.
//
//  Note on scope: `ExercisePlanner` is the bulk surface for *series* mutations
//  keyed on `seriesID`. A coach proposal targets one session on one day, so it
//  mutates that exercise directly. A member of a recurring series is edited in
//  isolation, matching the app's "apply to this one only" behavior.
//

import Foundation
import SwiftData
import AICoachCore

/// Applies accepted coach proposals to the model context.
enum CoachProposalApplier {

    /// Why a proposal could not be applied.
    enum Failure: Error, Equatable, LocalizedError {
        /// No session is scheduled on the proposed day.
        case noSessionOnDate(Date)
        /// More than one session is scheduled, so the target is ambiguous.
        case ambiguousDate(Date, count: Int)
        /// The session has already been recorded, so its plan is history.
        case alreadyRecorded(Date)
        /// A session already exists on the day an `.add` proposal targets.
        case dateAlreadyScheduled(Date)

        var errorDescription: String? {
            switch self {
            case .noSessionOnDate:
                return "There's nothing scheduled that day, so there's no session to change."
            case .ambiguousDate(_, let count):
                return "There are \(count) sessions that day — change the one you want directly."
            case .alreadyRecorded:
                return "That session is already recorded, so its plan can't be changed."
            case .dateAlreadyScheduled:
                return "Something is already scheduled that day."
            }
        }
    }

    // MARK: - Schedule changes

    /// Applies a schedule-change proposal.
    ///
    /// - Parameters:
    ///   - proposal: The accepted proposal.
    ///   - context: The context to mutate.
    /// - Returns: The affected exercise, or `nil` when the proposal removed it.
    /// - Throws: `Failure` when the proposal names no usable session.
    @discardableResult
    static func apply(
        _ proposal: ScheduleChangeProposal,
        in context: ModelContext
    ) throws -> Exercise? {
        if proposal.kind == .add {
            return try add(proposal, in: context)
        }

        let exercise = try resolveTarget(on: proposal.date, in: context)
        guard !exercise.isCompleted else {
            throw Failure.alreadyRecorded(proposal.date)
        }

        switch proposal.kind {
        case .adjustDistance:
            if let distance = proposal.distanceMiles {
                exercise.distanceMiles = distance
            }
        case .adjustDuration:
            if let duration = proposal.durationSeconds {
                exercise.durationSeconds = duration
            }
        case .changeType:
            if let type = proposal.exerciseType {
                let appType = ExerciseType(from: type)
                // Keep the name in step when it was just the type's label, the
                // same rule the record and add sheets follow.
                if exercise.name == exercise.type.rawValue {
                    exercise.name = appType.rawValue
                }
                exercise.type = appType
            }
        case .remove:
            // A series member is detached first so deleting it isn't read as a
            // statement about the rest of the series.
            if exercise.seriesID != nil {
                ExercisePlanner.detach(exercise)
            }
            context.delete(exercise)
            return nil
        case .add:
            break // handled above
        }
        return exercise
    }

    /// Inserts a new planned session for an `.add` proposal.
    private static func add(
        _ proposal: ScheduleChangeProposal,
        in context: ModelContext
    ) throws -> Exercise {
        guard sessions(on: proposal.date, in: context).isEmpty else {
            throw Failure.dateAlreadyScheduled(proposal.date)
        }
        guard let type = proposal.exerciseType else {
            // The decoder requires exercise_type for .add; this guards the
            // hand-constructed case.
            throw Failure.noSessionOnDate(proposal.date)
        }
        let appType = ExerciseType(from: type)
        let exercise = Exercise(
            name: appType.rawValue,
            type: appType,
            durationSeconds: proposal.durationSeconds ?? 0,
            distanceMiles: proposal.distanceMiles ?? 0,
            notes: proposal.rationale,
            date: proposal.date
        )
        context.insert(exercise)
        return exercise
    }

    /// Finds the single planned session on `date`.
    private static func resolveTarget(
        on date: Date,
        in context: ModelContext
    ) throws -> Exercise {
        let matches = sessions(on: date, in: context)
        switch matches.count {
        case 0: throw Failure.noSessionOnDate(date)
        case 1: return matches[0]
        default: throw Failure.ambiguousDate(date, count: matches.count)
        }
    }

    /// All exercises sharing a calendar day with `date`, earliest first.
    ///
    /// Filtered in memory: the comparison is by calendar day, which a
    /// `#Predicate` cannot express.
    private static func sessions(on date: Date, in context: ModelContext) -> [Exercise] {
        let all = (try? context.fetch(FetchDescriptor<Exercise>())) ?? []
        return all
            .filter { Calendar.current.isDate($0.date, inSameDayAs: date) }
            .sorted { $0.date < $1.date }
    }

    // MARK: - Strength day proposals

    /// What accepting a strength-day proposal did, for the confirmation note.
    struct StrengthDayOutcome: Equatable {
        /// Names of the exercises added to the lane, in board order.
        var inserted: [String]
        /// Names skipped because the lane's active section already has them.
        var skipped: [String]
    }

    /// Applies an accepted strength-day proposal: inserts the batch at the
    /// end of the weekday's active lane.
    ///
    /// Exercises are matched against the library by name (case-insensitive) so
    /// a known exercise keeps its provenance and canonical muscle group; an
    /// unmatched name becomes a plain entry carrying the proposed group. An
    /// exercise the lane already has — by name, case-insensitively, in the
    /// active section only — is skipped rather than duplicated, and reported
    /// in the outcome so the athlete hears about it. Nothing is removed or
    /// reordered: proposals add, never destroy.
    ///
    /// - Parameters:
    ///   - proposal: The accepted proposal.
    ///   - library: The merged exercise library (bundled + user entries).
    ///   - context: The context to mutate.
    /// - Returns: What was inserted and what was skipped.
    static func apply(
        _ proposal: StrengthDayProposal,
        library: [LibraryExercise],
        in context: ModelContext
    ) -> StrengthDayOutcome {
        let all = (try? context.fetch(FetchDescriptor<StrengthExercise>())) ?? []
        var laneNames = Set(
            all.filter { $0.weekdayIndex == proposal.weekdayIndex && !$0.isOffloaded }
                .map { normalized($0.name) }
        )
        var nextOrder = StrengthBoardPlanner.nextSortOrder(
            all, day: proposal.weekdayIndex, offloaded: false
        )
        var outcome = StrengthDayOutcome(inserted: [], skipped: [])

        for entry in proposal.exercises {
            let key = normalized(entry.name)
            guard !laneNames.contains(key) else {
                outcome.skipped.append(entry.name)
                continue
            }
            let match = library.first { normalized($0.name) == key }
            let exercise = StrengthExercise(
                name: match?.name ?? entry.name,
                libraryExerciseID: match?.id,
                muscleGroup: match?.muscleGroup ?? MuscleGroup(from: entry.muscleGroup),
                weekdayIndex: proposal.weekdayIndex,
                sortOrder: nextOrder,
                plannedSets: entry.plannedSets,
                plannedReps: entry.plannedReps
            )
            context.insert(exercise)
            laneNames.insert(key)
            nextOrder += 1
            outcome.inserted.append(exercise.name)
        }
        return outcome
    }

    /// Name normalization for duplicate detection and library matching:
    /// trimmed and case-folded, so "bench press" and "Bench Press " collide.
    private static func normalized(_ name: String) -> String {
        name.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    // MARK: - Workout proposals

    /// The form values a `WorkoutProposal` pre-fills in the record sheet.
    ///
    /// A workout proposal is never written straight through — it populates the
    /// sheet the athlete already knows, so they confirm the numbers the coach
    /// heard before anything lands in their history.
    struct WorkoutPrefill: Equatable {
        var name: String
        var type: ExerciseType
        var date: Date
        var distanceMiles: Double?
        var durationSeconds: Int
        var perceivedExertion: Int?
        var feeling: Int?
        var notes: String
    }

    /// Converts a proposal into record-sheet form values.
    ///
    /// Unstated fields stay unset rather than defaulting: `feeling` and
    /// `perceivedExertion` are independent, and a `nil` must survive to the
    /// form as "not recorded" rather than becoming a number the athlete never
    /// gave.
    static func prefill(from proposal: WorkoutProposal) -> WorkoutPrefill {
        let type = ExerciseType(from: proposal.exerciseType)
        return WorkoutPrefill(
            name: type.rawValue,
            type: type,
            date: proposal.date,
            distanceMiles: proposal.distanceMiles,
            durationSeconds: proposal.durationSeconds ?? 0,
            perceivedExertion: proposal.perceivedExertion,
            feeling: proposal.feeling,
            notes: proposal.notes ?? ""
        )
    }
}
