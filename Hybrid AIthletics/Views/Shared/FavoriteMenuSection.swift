//
//  FavoriteMenuSection.swift
//  Hybrid AIthletics
//
//  The "Start from Favorite" form section shared by the record (quick add)
//  and schedule sheets. Picking a favorite hands it back to the sheet, which
//  fills its own fields. Favorites arrive as a `let` from the presenting
//  top-level view — sheets don't own queries.
//

import SwiftUI

/// A form section with a menu of favorite workouts to pre-fill from.
struct FavoriteMenuSection: View {
    @Environment(\.useMetricUnits) private var useMetricUnits

    /// Favorites in their manual order.
    let favorites: [FavoriteWorkout]
    /// Called with the picked favorite.
    let onSelect: (FavoriteWorkout) -> Void

    var body: some View {
        Section {
            if favorites.isEmpty {
                Label("No favorites yet — add them from Home", systemImage: "star")
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("favoriteMenu.empty")
            } else {
                Menu {
                    ForEach(favorites) { favorite in
                        Button {
                            onSelect(favorite)
                        } label: {
                            Label(favorite.name, systemImage: favorite.type.systemImage)
                            let summary = favorite.targetSummary(metric: useMetricUnits)
                            if !summary.isEmpty {
                                Text(summary)
                            }
                        }
                        .accessibilityIdentifier("favoriteMenu.item.\(favorite.name)")
                    }
                } label: {
                    Label("Start from Favorite", systemImage: "star")
                }
                .accessibilityIdentifier("favoriteMenu.button")
            }
        }
    }
}

#Preview {
    Form {
        FavoriteMenuSection(
            favorites: [FavoriteWorkout(name: "Easy Loop", type: .easyRun, distanceMiles: 5)],
            onSelect: { _ in }
        )
        FavoriteMenuSection(favorites: [], onSelect: { _ in })
    }
}
