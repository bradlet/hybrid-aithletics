//
//  AddExerciseSheet.swift
//  Hybrid AIthletics
//
//  Form sheet for creating or editing a planned exercise.
//  Supports both create (nil exercise) and edit (existing exercise) modes.
//

import SwiftUI
import SwiftData

/// A form for creating a new exercise or editing an existing one.
struct AddExerciseSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.useMetricUnits) private var useMetricUnits

    /// The exercise to edit, or nil for create mode.
    let exercise: Exercise?
    /// The default date when creating a new exercise.
    let defaultDate: Date
    /// Favorites offered by the "Start from Favorite" menu in create mode.
    let favorites: [FavoriteWorkout]

    @State private var name = ""
    @State private var type: ExerciseType = .run
    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0
    @State private var distance: Double?
    @State private var notes = ""
    @State private var scheduledDate: Date
    @State private var countsTowardMileage = true

    // Recurrence (create mode only).
    @State private var cadence: SeriesCadence = .oneOff
    @State private var seriesEndDate: Date
    @State private var addProgression = false
    @State private var progressionEveryN = 1
    @State private var progressionDistanceDelta: Double?
    @State private var progressionDurationMinutes: Int?

    /// Whether the series-scope save dialog is showing (edit mode, series member).
    @State private var showSeriesSaveDialog = false

    init(exercise: Exercise?, defaultDate: Date, favorites: [FavoriteWorkout] = []) {
        self.exercise = exercise
        self.defaultDate = defaultDate
        self.favorites = favorites
        _scheduledDate = State(initialValue: defaultDate)
        let threeMonthsOut = Calendar.current.date(byAdding: .month, value: 3, to: defaultDate) ?? defaultDate
        _seriesEndDate = State(initialValue: threeMonthsOut)
    }

    /// Whether the form has enough data to save.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
        && (distance ?? 0) > 0
    }

    var body: some View {
        NavigationStack {
            Form {
                if exercise == nil {
                    FavoriteMenuSection(favorites: favorites) { apply($0) }
                }
                nameAndTypeSection
                durationSection
                distanceSection
                dateSection
                if exercise == nil {
                    recurrenceSection
                }
                notesSection
            }
            .navigationTitle(exercise == nil ? "Schedule Exercise" : "Edit Exercise")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        if exercise?.seriesID != nil {
                            showSeriesSaveDialog = true
                        } else {
                            save()
                        }
                    }
                    .disabled(!canSave)
                }
            }
            .confirmationDialog(
                "This exercise is part of a series.",
                isPresented: $showSeriesSaveDialog,
                titleVisibility: .visible
            ) {
                Button("Save This Exercise Only") { save() }
                Button("Save This + Future") { saveThisAndFuture() }
                Button("Cancel", role: .cancel) {}
            }
            .onAppear { populateFields() }
            .onChange(of: type) { oldType, newType in
                if name == oldType.rawValue {
                    name = newType.rawValue
                }
            }
        }
    }

    // MARK: - Form Sections

    /// Exercise type picker and name field (type first, name secondary).
    private var nameAndTypeSection: some View {
        Section {
            Picker("Type", selection: $type) {
                ForEach(ExerciseType.allCases) { exerciseType in
                    Label(exerciseType.rawValue, systemImage: exerciseType.systemImage)
                        .tag(exerciseType)
                }
            }
            TextField("Exercise name", text: $name)
                .foregroundStyle(name == type.rawValue ? .secondary : .primary)
        }
    }

    /// Duration pickers for hours, minutes, seconds.
    private var durationSection: some View {
        Section("Duration") {
            DurationWheelPickers(hours: $hours, minutes: $minutes, seconds: $seconds)
        }
    }

    /// Distance input field and mileage-counting toggle.
    private var distanceSection: some View {
        Section {
            HStack {
                TextField("0.0", value: $distance, format: .number.precision(.fractionLength(1)))
                    .keyboardType(.decimalPad)
                Text(useMetricUnits ? "km" : "mi")
                    .foregroundStyle(.secondary)
            }
            Toggle("Counts Toward Mileage", isOn: $countsTowardMileage)
                .accessibilityIdentifier("workoutForm.countsTowardMileageToggle")
        } header: {
            Text("Distance")
        } footer: {
            if !countsTowardMileage {
                Text("Distance is tracked but excluded from mileage totals.")
            }
        }
    }

    /// Date picker for scheduling.
    private var dateSection: some View {
        Section("Scheduled Date") {
            DatePicker("Date", selection: $scheduledDate, displayedComponents: .date)
        }
    }

    /// Recurrence controls: cadence, end date, and optional progression.
    /// Creating a recurring exercise bulk-inserts one concrete exercise per
    /// occurrence — there is no template to maintain afterward.
    private var recurrenceSection: some View {
        Section {
            Picker("Repeat", selection: $cadence) {
                ForEach(SeriesCadence.allCases) { cadence in
                    Text(cadence.displayName).tag(cadence)
                }
            }
            .accessibilityIdentifier("addExercise.cadencePicker")
            if cadence != .oneOff {
                DatePicker(
                    "End Date",
                    selection: $seriesEndDate,
                    in: scheduledDate...,
                    displayedComponents: .date
                )
                Toggle("Add Progression", isOn: $addProgression)
                if addProgression {
                    Stepper(
                        "Every \(progressionEveryN) occurrence\(progressionEveryN == 1 ? "" : "s")",
                        value: $progressionEveryN,
                        in: 1...12
                    )
                    HStack {
                        Text("Distance change")
                        Spacer()
                        TextField("0.0", value: $progressionDistanceDelta, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text(useMetricUnits ? "km" : "mi")
                            .foregroundStyle(.secondary)
                    }
                    HStack {
                        Text("Duration change")
                        Spacer()
                        TextField("0", value: $progressionDurationMinutes, format: .number)
                            .keyboardType(.numbersAndPunctuation)
                            .multilineTextAlignment(.trailing)
                            .frame(width: 80)
                        Text("min")
                            .foregroundStyle(.secondary)
                    }
                }
            }
        } footer: {
            if cadence != .oneOff {
                Text("\(plannedOccurrenceCount) exercises will be created.")
            }
        }
    }

    /// How many exercises the current recurrence settings would create.
    private var plannedOccurrenceCount: Int {
        SeriesGenerator.occurrences(for: currentSeriesSpec).count
    }

    /// Notes text field.
    private var notesSection: some View {
        Section("Notes") {
            TextField("Optional notes...", text: $notes, axis: .vertical)
                .lineLimit(3...6)
        }
    }

    // MARK: - Actions

    /// Pre-fills form fields from the exercise (edit mode) or defaults (create mode).
    private func populateFields() {
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
            notes = exercise.notes
            scheduledDate = exercise.date
            countsTowardMileage = exercise.countsTowardMileage
        } else {
            name = type.rawValue
            scheduledDate = defaultDate
        }
    }

    /// Fills the plan's identity and targets from a favorite, leaving the
    /// date, recurrence and notes as the athlete set them.
    private func apply(_ favorite: FavoriteWorkout) {
        let values = FavoriteFormValues(favorite, metric: useMetricUnits)
        name = values.name
        type = values.type
        hours = values.hours
        minutes = values.minutes
        seconds = values.seconds
        distance = values.displayDistance
        countsTowardMileage = values.countsTowardMileage
    }

    /// Planned duration from the wheel pickers, in seconds.
    private var enteredDurationSeconds: Int {
        hours * 3600 + minutes * 60 + seconds
    }

    /// Planned distance converted from display units to internal miles.
    private var enteredDistanceMiles: Double {
        useMetricUnits ? (distance ?? 0) / 1.60934 : (distance ?? 0)
    }

    /// The series spec described by the current form fields (create mode).
    private var currentSeriesSpec: ExerciseSeriesSpec {
        var progression: SeriesProgression?
        if addProgression {
            let deltaDisplay = progressionDistanceDelta ?? 0
            progression = SeriesProgression(
                everyN: progressionEveryN,
                distanceDeltaMiles: useMetricUnits ? deltaDisplay / 1.60934 : deltaDisplay,
                durationDeltaSeconds: (progressionDurationMinutes ?? 0) * 60
            )
        }
        return ExerciseSeriesSpec(
            name: name,
            type: type,
            startDate: scheduledDate,
            cadence: cadence,
            endDate: seriesEndDate,
            baseDistanceMiles: enteredDistanceMiles,
            baseDurationSeconds: enteredDurationSeconds,
            notes: notes,
            countsTowardMileage: countsTowardMileage,
            progression: progression
        )
    }

    /// Saves the exercise: updates the existing one in edit mode, otherwise
    /// creates a single exercise or a whole series depending on cadence.
    private func save() {
        if let exercise {
            applyFields(to: exercise)
        } else if cadence == .oneOff {
            let newExercise = Exercise(
                name: name,
                type: type,
                durationSeconds: enteredDurationSeconds,
                distanceMiles: enteredDistanceMiles,
                notes: notes,
                date: scheduledDate,
                countsTowardMileage: countsTowardMileage
            )
            modelContext.insert(newExercise)
        } else {
            ExercisePlanner.createSeries(currentSeriesSpec, in: modelContext)
        }
        dismiss()
    }

    /// Saves the edited exercise, then applies the same planned-field values
    /// to every later member of its series. Date changes stay on this
    /// exercise only.
    private func saveThisAndFuture() {
        guard let exercise, let seriesID = exercise.seriesID else {
            save()
            return
        }
        // Capture the scope boundary before the date edit can move it.
        let scopeStart = exercise.date
        applyFields(to: exercise)
        ExercisePlanner.updateSeries(
            seriesID,
            scope: .from(scopeStart),
            mutations: SeriesMutations(
                name: name,
                type: type,
                notes: notes,
                countsTowardMileage: countsTowardMileage,
                distanceMiles: enteredDistanceMiles,
                durationSeconds: enteredDurationSeconds
            ),
            in: modelContext
        )
        dismiss()
    }

    /// Writes the form fields onto the given exercise.
    private func applyFields(to exercise: Exercise) {
        exercise.name = name
        exercise.type = type
        exercise.durationSeconds = enteredDurationSeconds
        exercise.distanceMiles = enteredDistanceMiles
        exercise.notes = notes
        exercise.date = scheduledDate.startOfDay
        exercise.countsTowardMileage = countsTowardMileage
    }
}

#Preview {
    AddExerciseSheet(exercise: nil, defaultDate: Date())
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
