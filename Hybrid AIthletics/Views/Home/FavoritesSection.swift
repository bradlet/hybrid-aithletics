//
//  FavoritesSection.swift
//  Hybrid AIthletics
//
//  The Home card for favorite workouts: one chip per favorite that
//  quick-records it for today, plus the Edit entry point into managing them.
//

import SwiftUI

/// A horizontal row of favorite-workout chips with an Edit button.
struct FavoritesSection: View {
    /// Favorites in their manual order.
    let favorites: [FavoriteWorkout]
    /// Called when a chip is tapped, to record that favorite for today.
    let onSelect: (FavoriteWorkout) -> Void
    /// Called to open the favorites manager.
    let onEdit: () -> Void
    /// Called from the empty state to create the first favorite.
    let onAdd: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack {
                Text("Favorites")
                    .font(.headline)
                Spacer()
                Button("Edit", action: onEdit)
                    .font(.subheadline)
                    .accessibilityIdentifier("home.favorites.edit")
            }

            if favorites.isEmpty {
                emptyState
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(favorites) { favorite in
                            chip(for: favorite)
                        }
                    }
                }
            }
        }
    }

    /// Prompt shown before any favorite exists.
    private var emptyState: some View {
        Button(action: onAdd) {
            Label("Save workouts you repeat", systemImage: "star")
                .font(.subheadline)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(
                    RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .strokeBorder(Color.accentColor.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [4]))
                )
                .foregroundStyle(Color.accentColor)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.favorites.add")
    }

    /// A tappable chip showing the favorite's type icon and name.
    private func chip(for favorite: FavoriteWorkout) -> some View {
        Button {
            onSelect(favorite)
        } label: {
            Label(favorite.name, systemImage: favorite.type.systemImage)
                .font(.subheadline.weight(.medium))
                .lineLimit(1)
                .padding(.horizontal, 14)
                .padding(.vertical, 10)
                .background(
                    Capsule().fill(favorite.type.color.opacity(0.15))
                )
                .foregroundStyle(favorite.type.color)
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("home.favorites.chip.\(favorite.name)")
    }
}

#Preview {
    VStack(spacing: 24) {
        FavoritesSection(
            favorites: [
                FavoriteWorkout(name: "Easy Loop", type: .easyRun, distanceMiles: 5),
                FavoriteWorkout(name: "Pool", type: .swim, sortOrder: 1)
            ],
            onSelect: { _ in }, onEdit: {}, onAdd: {}
        )
        FavoritesSection(favorites: [], onSelect: { _ in }, onEdit: {}, onAdd: {})
    }
    .padding()
}
