//
//  RatingVisuals.swift
//  Hybrid AIthletics
//
//  Shared display-name / SF Symbol / tint mappings for the two subjective
//  workout ratings: how the athlete felt (1–5) and how hard the session was
//  (RPE, 1–10). Single source of truth so the `RadialRatingPicker` used for
//  data entry and the "Feeling like" stat card in `SummaryStatsView` render
//  the same face and tint for the same value.
//
//  Kept free of view code so the mappings are unit-testable.
//

import SwiftUI

// MARK: - Feeling

/// Stateless 1–5 feeling → name / face / tint mapping.
///
/// The scale runs 1 (very weak) to 5 (very strong); `nil` means the athlete
/// did not record a feeling. None of SF Symbols' face glyphs actually frown,
/// so the sad → happy meaning is carried by the red → green tint ramp while
/// the glyphs progress from dashed placeholder through filled to inverse.
enum FeelingVisuals {

    /// Valid values on the feeling scale.
    static let range = 1...5

    /// Plain-English name for a feeling level.
    /// - Parameter feeling: Feeling level, or `nil` for unset.
    /// - Returns: A display name; `"Not set"` for `nil` or out-of-range input.
    static func displayName(for feeling: Int?) -> String {
        switch feeling {
        case 1:  return "Very Weak"
        case 2:  return "Weak"
        case 3:  return "Normal"
        case 4:  return "Strong"
        case 5:  return "Very Strong"
        default: return "Not set"
        }
    }

    /// SF Symbol face for a feeling level.
    /// - Parameter feeling: Feeling level, or `nil` for unset.
    /// - Returns: A symbol name; the neutral `smiley` outline for `nil` or
    ///   out-of-range input.
    static func symbolName(for feeling: Int?) -> String {
        switch feeling {
        case 1:  return "face.dashed"
        case 2:  return "face.dashed.fill"
        case 3:  return "face.smiling"
        case 4:  return "face.smiling.fill"
        case 5:  return "face.smiling.inverse"
        default: return "smiley"
        }
    }

    /// Red → green tint for a feeling level via HSB interpolation, so a weak
    /// session reads hot and a strong one reads cool.
    /// - Parameter feeling: Feeling level, or `nil` for unset.
    /// - Returns: A tint; `.secondary` for `nil`, matching the neutral face.
    static func tint(for feeling: Int?) -> Color {
        guard let feeling else { return .secondary }
        let span = Double(range.upperBound - range.lowerBound)
        let clamped = Double(min(max(feeling, range.lowerBound), range.upperBound) - range.lowerBound) / span
        let hue = 0.0 + (0.37 * clamped)  // ~red → ~green
        return Color(hue: hue, saturation: 0.78, brightness: 0.92)
    }
}

// MARK: - Perceived exertion

/// Stateless 1–10 perceived-exertion (RPE) → name / tint mapping.
///
/// Labels match Garmin's perceived-effort scale word for word, so a rating
/// copied from a Garmin activity reads the same here.
enum ExertionVisuals {

    /// Valid values on the perceived-exertion scale.
    static let range = 1...10

    /// Plain-English name for a perceived-exertion level, using Garmin's
    /// labels: Very Light → Light → Moderate → Somewhat Hard → Hard →
    /// Very Hard → Extremely Hard → Maximum.
    /// - Parameter exertion: RPE level, or `nil` for unset.
    /// - Returns: A display name; `"Not set"` for `nil` or out-of-range input.
    static func displayName(for exertion: Int?) -> String {
        switch exertion {
        case 1:     return "Very Light"
        case 2:     return "Light"
        case 3:     return "Moderate"
        case 4:     return "Somewhat Hard"
        case 5, 6:  return "Hard"
        case 7, 8:  return "Very Hard"
        case 9:     return "Extremely Hard"
        case 10:    return "Maximum"
        default:    return "Not set"
        }
    }

    /// Green → red tint for a perceived-exertion level. Deliberately the
    /// inverse of `FeelingVisuals.tint`: for exertion the *high* end is hot.
    /// - Parameter exertion: RPE level, or `nil` for unset.
    /// - Returns: A tint; `.secondary` for `nil`.
    static func tint(for exertion: Int?) -> Color {
        guard let exertion else { return .secondary }
        let span = Double(range.upperBound - range.lowerBound)
        let clamped = Double(min(max(exertion, range.lowerBound), range.upperBound) - range.lowerBound) / span
        let hue = 0.37 - (0.37 * clamped)  // ~green → ~red
        return Color(hue: hue, saturation: 0.78, brightness: 0.92)
    }
}
