//
//  ModelContainerFactory.swift
//  Hybrid AIthletics
//
//  Centralizes ModelContainer creation for the app, previews, and tests.
//  Configures SwiftData with CloudKit sync.
//

import Foundation
import SwiftData

/// Factory for creating configured ModelContainer instances.
enum ModelContainerFactory {

    /// The full schema used by the app.
    private static var schema: Schema {
        Schema([Exercise.self, StrengthExercise.self, UserLibraryExercise.self, FavoriteWorkout.self, AppConfiguration.self])
    }

    /// Creates the production ModelContainer with CloudKit sync enabled.
    /// - Returns: A configured ModelContainer.
    static func makeContainer() -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: false,
            cloudKitDatabase: .automatic
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }

    /// Creates an in-memory ModelContainer for SwiftUI previews and unit tests.
    /// - Returns: An in-memory ModelContainer with no persistence.
    static func makePreviewContainer() -> ModelContainer {
        let config = ModelConfiguration(
            schema: schema,
            isStoredInMemoryOnly: true
        )
        do {
            return try ModelContainer(for: schema, configurations: [config])
        } catch {
            fatalError("Could not create preview ModelContainer: \(error)")
        }
    }
}
