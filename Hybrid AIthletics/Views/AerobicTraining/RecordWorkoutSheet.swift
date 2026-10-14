//
//  RecordWorkoutSheet.swift
//  Hybrid AIthletics
//
//  Form sheet for recording a completed workout.
//  When given a planned exercise, pre-fills from its targets and attaches the
//  recorded actuals to that exercise's nested `workout`. When exercise is nil
//  (quick add), creates a new completed Exercise whose planned targets mirror
//  the recorded actuals.
//

import SwiftUI
import SwiftData

/// A form for recording a workout, optionally pre-filled from a planned exercise.
struct RecordWorkoutSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.useMetricUnits) private var useMetricUnits
    @Environment(\.googleSheetsSync) private var sheetsSync

    /// The exercise template to pre-fill defaults from, or nil for quick add.
    let exercise: Exercise?
    /// The default date for the workout (used when exercise is nil).
    let defaultDate: Date
    /// Values proposed by the AI coach, or nil for a normal entry.
    ///
    /// A coach proposal never writes straight through — it populates this form
    /// so the athlete confirms the numbers the coach heard before anything
    /// lands in their history.
    var prefill: CoachProposalApplier.WorkoutPrefill? = nil

    @State private var name = ""
    @State private var type: ExerciseType = .run
    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0
    @State private var distance: Double?
    @State private var notes = ""
    @State private var workoutDate = Date()
    @State private var feeling: Int?
    @State private var perceivedExertion: Int?
    @State private var countsTowardMileage = true
    @State private var previousType: ExerciseType = .run

    /// Whether the form has enough data to save.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                WorkoutFormFields(
                    name: $name,
                    type: $type,
                    hours: $hours,
                    minutes: $minutes,
                    seconds: $seconds,
                    distance: $distance,
                    date: $workoutDate,
                    notes: $notes,
                    feeling: $feeling,
                    perceivedExertion: $perceivedExertion,
                    countsTowardMileage: $countsTowardMileage
                )
            }
            .navigationTitle("Record Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                }
            }
            .onAppear { populateFields() }
            .onChange(of: type) { oldType, newType in
                if name == oldType.rawValue {
                    name = newType.rawValue
                }
            }
        }
    }

    // MARK: - Actions

    /// Pre-fills form fields from the source exercise template or defaults.
    private func populateFields() {
        if let prefill {
            populate(from: prefill)
            return
        }
        if let exercise {
            name = exercise.name
            type = exercise.type
            let total = exercise.durationSeconds
            hours = total / 3600
            minutes = (total % 3600) / 60
            seconds = total % 60
            // Leave the field empty (placeholder) when there is no target
            // distance rather than pre-filling a literal 0.0.
            if exercise.distanceMiles > 0 {
                distance = useMetricUnits ? exercise.distanceMiles.toDisplayDistance(metric: true) : exercise.distanceMiles
            }
            countsTowardMileage = exercise.countsTowardMileage
            previousType = exercise.type
        } else {
            name = type.rawValue
            previousType = type
        }
        workoutDate = defaultDate
    }

    /// Fills the form from a coach proposal.
    ///
    /// Unstated values stay unset: `feeling` and `perceivedExertion` are
    /// independent, and a nil must arrive at the dials as "not recorded"
    /// rather than as a number the athlete never gave.
    private func populate(from prefill: CoachProposalApplier.WorkoutPrefill) {
        name = prefill.name
        type = prefill.type
        previousType = prefill.type
        hours = prefill.durationSeconds / 3600
        minutes = (prefill.durationSeconds % 3600) / 60
        seconds = prefill.durationSeconds % 60
        if let miles = prefill.distanceMiles, miles > 0 {
            distance = useMetricUnits ? miles.toDisplayDistance(metric: true) : miles
        }
        notes = prefill.notes
        feeling = prefill.feeling
        perceivedExertion = prefill.perceivedExertion
        workoutDate = prefill.date
    }

    /// Records the workout. When recording a planned exercise, its planned
    /// targets are left intact and the form values become the recorded
    /// actuals on `exercise.workout`. On quick add, a new completed exercise
    /// is created with planned targets mirroring the actuals.
    private func save() {
        let durationSec = hours * 3600 + minutes * 60 + seconds
        let displayDistance = distance ?? 0
        let distanceMiles = useMetricUnits ? displayDistance / 1.60934 : displayDistance

        let workout = Workout(
            durationSeconds: durationSec,
            distanceMiles: distanceMiles,
            notes: notes,
            feeling: feeling,
            perceivedExertion: perceivedExertion,
            source: WorkoutSource.manual.rawValue
        )

        if let exercise {
            // Keep planned targets; attach actuals and update identity/date.
            exercise.name = name
            exercise.type = type
            exercise.date = workoutDate
            exercise.countsTowardMileage = countsTowardMileage
            exercise.workout = workout
        } else {
            let newExercise = Exercise(
                name: name,
                type: type,
                durationSeconds: durationSec,
                distanceMiles: distanceMiles,
                notes: notes,
                date: workoutDate,
                countsTowardMileage: countsTowardMileage,
                workout: workout
            )
            modelContext.insert(newExercise)
        }
        // Explicit save so the Google Sheets sync trigger sees the new
        // record immediately when it fetches via a fresh ModelContext.
        try? modelContext.save()
        sheetsSync.requestSync()
        dismiss()
    }
}

#Preview {
    let container = ModelContainerFactory.makePreviewContainer()
    let exercise = Exercise(
        name: "Morning Run",
        type: .run,
        durationSeconds: 1800,
        distanceMiles: 3.0,
        date: Date()
    )
    return RecordWorkoutSheet(exercise: exercise, defaultDate: Date())
        .modelContainer(container)
}
