//
//  ManageFavoritesSheet.swift
//  Hybrid AIthletics
//
//  The favorites list behind the Home card's Edit button: add, edit,
//  swipe-delete and drag-reorder favorite workouts. Receives the favorites as
//  a `let` from `HomeView`, which owns the query.
//

import SwiftUI
import SwiftData

/// A sheet listing every favorite workout for management.
struct ManageFavoritesSheet: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.dismiss) private var dismiss
    @Environment(\.useMetricUnits) private var useMetricUnits

    /// Favorites in their manual order.
    let favorites: [FavoriteWorkout]

    /// Identifies which form the sheet is showing: a new favorite or an edit.
    private struct FormRequest: Identifiable {
        let id = UUID()
        let favorite: FavoriteWorkout?
    }

    @State private var formRequest: FormRequest?

    var body: some View {
        NavigationStack {
            List {
                if favorites.isEmpty {
                    ContentUnavailableView(
                        "No Favorites",
                        systemImage: "star",
                        description: Text("Save workouts you repeat to pre-fill them when recording or scheduling.")
                    )
                }
                ForEach(favorites) { favorite in
                    Button {
                        formRequest = FormRequest(favorite: favorite)
                    } label: {
                        row(for: favorite)
                    }
                    .foregroundStyle(.primary)
                    .accessibilityIdentifier("manageFavorites.row.\(favorite.name)")
                }
                .onDelete(perform: delete)
                .onMove(perform: move)
            }
            .navigationTitle("Favorites")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Done") { dismiss() }
                        .accessibilityIdentifier("manageFavorites.done")
                }
                ToolbarItemGroup(placement: .primaryAction) {
                    if !favorites.isEmpty { EditButton() }
                    Button {
                        formRequest = FormRequest(favorite: nil)
                    } label: {
                        Label("Add Favorite", systemImage: "plus")
                    }
                    .accessibilityIdentifier("manageFavorites.add")
                }
            }
            .sheet(item: $formRequest) { request in
                FavoriteWorkoutFormSheet(favorite: request.favorite)
            }
        }
    }

    /// A favorite's type icon, name and target summary.
    private func row(for favorite: FavoriteWorkout) -> some View {
        HStack(spacing: 12) {
            Image(systemName: favorite.type.systemImage)
                .foregroundStyle(favorite.type.color)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 2) {
                Text(favorite.name)
                let summary = favorite.targetSummary(metric: useMetricUnits)
                Text(summary.isEmpty ? favorite.type.rawValue : "\(favorite.type.rawValue) · \(summary)")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
    }

    // MARK: - Actions

    /// Deletes the favorites at the swiped offsets.
    private func delete(at offsets: IndexSet) {
        for index in offsets {
            try? FavoriteWorkoutEditor.delete(favorites[index], in: modelContext)
        }
    }

    /// Persists a drag reorder.
    private func move(from source: IndexSet, to destination: Int) {
        FavoriteWorkoutEditor.move(favorites, fromOffsets: source, toOffset: destination)
        try? modelContext.save()
    }
}

#Preview {
    ManageFavoritesSheet(favorites: [
        FavoriteWorkout(name: "Easy Loop", type: .easyRun, distanceMiles: 5, durationSeconds: 2700),
        FavoriteWorkout(name: "Pool", type: .swim, durationSeconds: 1800, sortOrder: 1)
    ])
    .modelContainer(ModelContainerFactory.makePreviewContainer())
}
