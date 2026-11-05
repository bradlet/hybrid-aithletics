//
//  WorkoutDetailSheet.swift
//  Hybrid AIthletics
//
//  Edit/delete sheet for a recorded exercise (one whose `workout` is set).
//  Opens directly in editable mode, shows every user-facing field
//  (intentionally omitting the `source` and `externalID` provenance fields
//  owned by the import pipeline), and supports destructive delete via a
//  confirmation dialog.
//
//  Shares its form layout with `RecordWorkoutSheet` via `WorkoutFormFields`.
//

import SwiftUI
import SwiftData

/// A form sheet that lets the user edit or delete a previously-recorded workout.
struct WorkoutDetailSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.useMetricUnits) private var useMetricUnits
    @Environment(\.googleSheetsSync) private var sheetsSync

    /// The recorded exercise being edited. Mutated in-place on save.
    let exercise: Exercise

    @State private var name: String
    @State private var type: ExerciseType
    @State private var hours: Int
    @State private var minutes: Int
    @State private var seconds: Int
    @State private var distance: Double?
    @State private var plannedHours: Int
    @State private var plannedMinutes: Int
    @State private var plannedSeconds: Int
    @State private var plannedDistance: Double?
    @State private var date: Date
    @State private var notes: String
    @State private var feeling: Int?
    @State private var perceivedExertion: Int?
    @State private var countsTowardMileage: Bool
    @State private var showDeleteConfirmation = false
    /// Whether the new-favorite form seeded from this workout is showing.
    @State private var isSavingFavorite = false
    /// Tracks whether the distance fields have been converted from their raw
    /// (miles) seed values into the user's display unit. `@Environment` is
    /// not available during `init`, so the conversion runs once in `.onAppear`.
    @State private var hasConvertedDistance = false

    /// The recorded actuals miles seed used for the display-unit conversion.
    private var recordedMiles: Double { exercise.workout?.distanceMiles ?? exercise.distanceMiles }

    init(exercise: Exercise) {
        self.exercise = exercise
        let workout = exercise.workout
        _name = State(initialValue: exercise.name)
        _type = State(initialValue: exercise.type)
        let total = workout?.durationSeconds ?? exercise.durationSeconds
        _hours = State(initialValue: total / 3600)
        _minutes = State(initialValue: (total % 3600) / 60)
        _seconds = State(initialValue: total % 60)
        let plannedTotal = exercise.durationSeconds
        _plannedHours = State(initialValue: plannedTotal / 3600)
        _plannedMinutes = State(initialValue: (plannedTotal % 3600) / 60)
        _plannedSeconds = State(initialValue: plannedTotal % 60)
        // Seed with raw miles; converted to display units in .onAppear once
        // `useMetricUnits` is available from the environment. Zero distances
        // seed as nil so the field shows its placeholder instead of "0.0".
        let recordedMiles = workout?.distanceMiles ?? exercise.distanceMiles
        _distance = State(initialValue: recordedMiles > 0 ? recordedMiles : nil)
        _plannedDistance = State(initialValue: exercise.distanceMiles > 0 ? exercise.distanceMiles : nil)
        _date = State(initialValue: exercise.date)
        _notes = State(initialValue: workout?.notes ?? "")
        // `workout?.feeling` is Int?? — flatten so an absent workout and an
        // unrated one both seed as nil.
        _feeling = State(initialValue: workout?.feeling ?? nil)
        _perceivedExertion = State(initialValue: workout?.perceivedExertion ?? nil)
        _countsTowardMileage = State(initialValue: exercise.countsTowardMileage)
    }

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
                    date: $date,
                    notes: $notes,
                    feeling: $feeling,
                    perceivedExertion: $perceivedExertion,
                    countsTowardMileage: $countsTowardMileage,
                    usesCompletedHeaders: true
                ) {
                    PlannedTargetFields(
                        distance: $plannedDistance,
                        hours: $plannedHours,
                        minutes: $plannedMinutes,
                        seconds: $plannedSeconds,
                        completedDistance: distance
                    )
                }
                saveAsFavoriteSection
                deleteSection
            }
            .navigationTitle("Edit Workout")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("workoutDetail.saveButton")
                }
            }
            .onAppear { convertDistanceForDisplayIfNeeded() }
            .sheet(isPresented: $isSavingFavorite) {
                FavoriteWorkoutFormSheet(favorite: nil, initialValues: favoriteSeed)
            }
            .alert(
                "Delete \(exercise.name)?",
                isPresented: $showDeleteConfirmation
            ) {
                // Ordering matters: SwiftUI renders the cancel role button
                // last regardless of declaration order. We want "Delete" to
                // be the distinct, testable label. No custom
                // `.accessibilityIdentifier` — SwiftUI double-wraps
                // identified buttons inside alerts which breaks XCUI
                // disambiguation.
                Button("Delete", role: .destructive) { performDelete() }
                Button("Cancel", role: .cancel) { }
            } message: {
                Text("This workout will be permanently removed.")
            }
        }
    }

    // MARK: - Sections

    private var saveAsFavoriteSection: some View {
        Section {
            Button {
                isSavingFavorite = true
            } label: {
                Label("Save as Favorite", systemImage: "star")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("workoutDetail.saveAsFavorite")
        }
    }

    /// The favorite this workout seeds, from the form as it stands: planned
    /// targets first, the recorded actuals filling any unset target.
    private var favoriteSeed: FavoriteFormValues {
        FavoriteFormValues.plannedFirst(
            name: name,
            type: type,
            plannedDurationSeconds: FavoriteFormValues.durationSeconds(
                hours: plannedHours, minutes: plannedMinutes, seconds: plannedSeconds
            ),
            plannedDisplayDistance: plannedDistance,
            actualDurationSeconds: FavoriteFormValues.durationSeconds(hours: hours, minutes: minutes, seconds: seconds),
            actualDisplayDistance: distance,
            countsTowardMileage: countsTowardMileage
        )
    }

    private var deleteSection: some View {
        Section {
            Button {
                performRemoveRecording()
            } label: {
                Label("Remove Recorded Workout", systemImage: "arrow.uturn.backward")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("workoutDetail.removeRecordingButton")
            Button(role: .destructive) {
                if Self.isRunningUITests {
                    // In UI tests, bypass the confirmation alert — SwiftUI's
                    // nested alert button structure breaks XCUI automation,
                    // and we have a dedicated unit test covering the
                    // `WorkoutEditor` delete path. UI tests verify the
                    // end-to-end wiring (tap → delete → list refresh).
                    performDelete()
                } else {
                    showDeleteConfirmation = true
                }
            } label: {
                Label("Delete Workout", systemImage: "trash")
                    .frame(maxWidth: .infinity, alignment: .center)
            }
            .accessibilityIdentifier("workoutDetail.deleteButton")
        }
    }

    /// True when the app was launched for UI tests with `-uiTestSeed`.
    /// Used to skip modal confirmations that aren't reliably driveable
    /// via XCUIApplication.
    private static var isRunningUITests: Bool {
        CommandLine.arguments.contains("-uiTestSeed")
    }

    // MARK: - Actions

    /// On first appear, convert the seeded raw-miles distance fields to the
    /// user's display unit. Guarded so repeated `onAppear` calls don't
    /// re-convert.
    private func convertDistanceForDisplayIfNeeded() {
        guard !hasConvertedDistance else { return }
        hasConvertedDistance = true
        if useMetricUnits {
            distance = distance.map { _ in recordedMiles.toDisplayDistance(metric: true) }
            plannedDistance = plannedDistance.map { _ in exercise.distanceMiles.toDisplayDistance(metric: true) }
        }
    }

    /// Persists all edits back to the exercise via `WorkoutEditor.apply`.
    private func save() {
        let displayDistance = distance ?? 0
        let displayPlannedDistance = plannedDistance ?? 0
        let distanceMiles = useMetricUnits ? displayDistance / 1.60934 : displayDistance
        let plannedDistanceMiles = useMetricUnits ? displayPlannedDistance / 1.60934 : displayPlannedDistance
        let edits = WorkoutEditor.EditedValues(
            name: name,
            type: type,
            durationSeconds: hours * 3600 + minutes * 60 + seconds,
            distanceMiles: distanceMiles,
            plannedDurationSeconds: plannedHours * 3600 + plannedMinutes * 60 + plannedSeconds,
            plannedDistanceMiles: plannedDistanceMiles,
            date: date.startOfDay,
            notes: notes,
            feeling: feeling,
            perceivedExertion: perceivedExertion,
            countsTowardMileage: countsTowardMileage
        )
        WorkoutEditor.apply(edits, to: exercise)
        // Explicit save so the Google Sheets sync trigger sees the edit
        // immediately when it fetches via a fresh ModelContext.
        try? modelContext.save()
        sheetsSync.requestSync()
        dismiss()
    }

    /// Clears the recorded workout (un-completes the exercise), keeping the
    /// planned exercise intact. Recoverable by re-recording, so no
    /// confirmation alert.
    private func performRemoveRecording() {
        WorkoutEditor.removeRecording(from: exercise)
        try? modelContext.save()
        sheetsSync.requestSync()
        dismiss()
    }

    /// Removes the exercise from the SwiftData context and dismisses the sheet.
    /// An explicit `save()` ensures the deletion is flushed to persistent
    /// state before `@Query` in the parent view re-evaluates — autosave
    /// timing is not reliable enough for an immediate list refresh.
    private func performDelete() {
        modelContext.delete(exercise)
        try? modelContext.save()
        sheetsSync.requestSync()
        dismiss()
    }
}

/// Stateless helper that applies a set of edited values to a recorded
/// `Exercise`. Extracted from `WorkoutDetailSheet.save()` so the mutation
/// logic can be unit-tested without instantiating a SwiftUI view hierarchy.
enum WorkoutEditor {
    /// The full set of user-editable fields for a recorded exercise.
    /// Intentionally excludes `source` and `externalID` (import-pipeline
    /// provenance), which are preserved across edits.
    struct EditedValues: Equatable {
        var name: String
        var type: ExerciseType
        var durationSeconds: Int
        /// Distance in miles — the caller is responsible for converting any
        /// km display values back to miles before constructing this struct.
        var distanceMiles: Double
        /// Planned target duration in seconds (the exercise's own metric).
        var plannedDurationSeconds: Int
        /// Planned target distance in miles — caller converts from km display.
        var plannedDistanceMiles: Double
        var date: Date
        var notes: String
        /// Subjective 1-5 feeling; `nil` when unrated.
        var feeling: Int?
        /// Subjective 1-10 perceived exertion; `nil` when unrated.
        var perceivedExertion: Int?
        /// Whether the exercise's distance counts toward mileage aggregates.
        var countsTowardMileage: Bool = true
    }

    /// Writes the edited identity fields (`name`, `type`, `date`) and planned
    /// targets onto the exercise, and rebuilds its nested `workout` from the
    /// edited actuals, preserving the existing `source` / `externalID`.
    /// Does not touch the exercise `id`.
    static func apply(_ edits: EditedValues, to exercise: Exercise) {
        exercise.name = edits.name
        exercise.type = edits.type
        exercise.date = edits.date
        exercise.durationSeconds = edits.plannedDurationSeconds
        exercise.distanceMiles = edits.plannedDistanceMiles
        exercise.countsTowardMileage = edits.countsTowardMileage
        let existing = exercise.workout
        exercise.workout = Workout(
            durationSeconds: edits.durationSeconds,
            distanceMiles: edits.distanceMiles,
            notes: edits.notes,
            feeling: edits.feeling,
            perceivedExertion: edits.perceivedExertion,
            source: existing?.source ?? WorkoutSource.manual.rawValue,
            externalID: existing?.externalID
        )
    }

    /// Clears the exercise's recorded workout, reverting it to a planned
    /// (uncompleted) state. Identity and planned targets are untouched.
    static func removeRecording(from exercise: Exercise) {
        exercise.workout = nil
    }
}

#Preview {
    let container = ModelContainerFactory.makePreviewContainer()
    let exercise = Exercise(
        name: "Tempo Run",
        type: .tempoRun,
        durationSeconds: 1800,
        distanceMiles: 4.0,
        notes: "Tempo Thursday.",
        date: Date(),
        workout: Workout(
            durationSeconds: 1800,
            distanceMiles: 4.0,
            notes: "Legs felt springy today.",
            feeling: 4,
            perceivedExertion: 7
        )
    )
    container.mainContext.insert(exercise)
    return WorkoutDetailSheet(exercise: exercise)
        .modelContainer(container)
}
