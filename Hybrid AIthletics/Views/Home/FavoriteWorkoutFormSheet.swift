//
//  FavoriteWorkoutFormSheet.swift
//  Hybrid AIthletics
//
//  Create/edit form for a favorite workout. Holds only the preset's identity
//  and targets — no date, notes or ratings, which belong to a workout, not a
//  preset. Mutations go through `FavoriteWorkoutEditor`.
//

import SwiftUI
import SwiftData

/// A form sheet that creates a favorite workout or edits an existing one.
struct FavoriteWorkoutFormSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.useMetricUnits) private var useMetricUnits

    /// The favorite being edited, or nil to create a new one.
    let favorite: FavoriteWorkout?
    /// Values to seed a new favorite with (Save as Favorite), or nil for a blank form.
    var initialValues: FavoriteFormValues? = nil

    @State private var name = ""
    @State private var type: ExerciseType = .run
    @State private var hours = 0
    @State private var minutes = 0
    @State private var seconds = 0
    @State private var distance: Double?
    @State private var countsTowardMileage = true
    /// Guards `populateFields` so returning from a pushed picker doesn't reset edits.
    @State private var hasPopulated = false

    /// Whether the form has enough data to save.
    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Picker("Type", selection: $type) {
                        ForEach(ExerciseType.allCases) { exerciseType in
                            Label(exerciseType.rawValue, systemImage: exerciseType.systemImage)
                                .tag(exerciseType)
                        }
                    }
                    TextField("Favorite name", text: $name)
                        .foregroundStyle(name == type.rawValue ? .secondary : .primary)
                        .accessibilityIdentifier("favoriteForm.nameField")
                }
                Section("Duration") {
                    DurationWheelPickers(hours: $hours, minutes: $minutes, seconds: $seconds)
                }
                Section {
                    HStack {
                        TextField("0.0", value: $distance, format: .number.precision(.fractionLength(1)))
                            .keyboardType(.decimalPad)
                            .accessibilityIdentifier("favoriteForm.distanceField")
                        Text(useMetricUnits ? "km" : "mi")
                            .foregroundStyle(.secondary)
                    }
                    Toggle("Counts Toward Mileage", isOn: $countsTowardMileage)
                } header: {
                    Text("Distance")
                } footer: {
                    if !countsTowardMileage {
                        Text("Distance is tracked but excluded from mileage totals.")
                    }
                }
            }
            .navigationTitle(favorite == nil ? "New Favorite" : "Edit Favorite")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") { save() }
                        .disabled(!canSave)
                        .accessibilityIdentifier("favoriteForm.saveButton")
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

    /// Seeds the form from the edited favorite, the Save-as values, or defaults.
    private func populateFields() {
        guard !hasPopulated else { return }
        hasPopulated = true
        let values = favorite.map { FavoriteFormValues($0, metric: useMetricUnits) }
            ?? initialValues
            ?? FavoriteFormValues(name: type.rawValue, type: type)
        name = values.name
        type = values.type
        hours = values.hours
        minutes = values.minutes
        seconds = values.seconds
        distance = values.displayDistance
        countsTowardMileage = values.countsTowardMileage
    }

    /// Creates or updates the favorite and dismisses.
    private func save() {
        let values = FavoriteFormValues(
            name: name,
            type: type,
            durationSeconds: FavoriteFormValues.durationSeconds(hours: hours, minutes: minutes, seconds: seconds),
            displayDistance: distance,
            countsTowardMileage: countsTowardMileage
        )
        if let favorite {
            guard FavoriteWorkoutEditor.update(favorite, with: values, metric: useMetricUnits) else { return }
            try? modelContext.save()
        } else {
            guard (try? FavoriteWorkoutEditor.make(from: values, metric: useMetricUnits, in: modelContext)) != nil
            else { return }
        }
        dismiss()
    }
}

#Preview {
    FavoriteWorkoutFormSheet(favorite: nil)
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
