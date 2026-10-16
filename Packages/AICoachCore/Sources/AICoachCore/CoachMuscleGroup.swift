//
//  CoachMuscleGroup.swift
//  AICoachCore
//
//  Muscle group enum with raw values matching the app's MuscleGroup.
//  Contains only the data needed for prompt building and tool payloads —
//  no UI properties (color), which remain in the app.
//

import Foundation

/// A muscle group targeted by a strength exercise. Raw values match the
/// app's `MuscleGroup` enum so conversions are lossless.
public enum CoachMuscleGroup: String, Codable, CaseIterable, Sendable {
    case chest = "Chest"
    case back = "Back"
    case shoulders = "Shoulders"
    case biceps = "Biceps"
    case triceps = "Triceps"
    case forearms = "Forearms"
    case core = "Core"
    case quads = "Quads"
    case hamstrings = "Hamstrings"
    case glutes = "Glutes"
    case calves = "Calves"
    case fullBody = "Full Body"
    case other = "Other"
}
