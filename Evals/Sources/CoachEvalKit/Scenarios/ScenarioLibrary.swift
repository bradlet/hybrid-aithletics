//
//  ScenarioLibrary.swift
//  CoachEvalKit
//
//  Every scenario the suite knows, and lookup by id or tag. Scenarios live in
//  one file per area (`RecordScenarios.swift`, ...) as extensions on this
//  enum; add a new one there and list it in `all`.
//

import Foundation

/// The suite's scenarios.
public enum ScenarioLibrary {

    /// All scenarios, in the order `run` executes them.
    public static let all: [EvalScenario] = [
        recordYesterday,
        recordAskFirst,
        recordAfterDetails,
        recordSeparateRatings,
        scheduleShortenTomorrow,
        overtrainingAdvice,
        strengthPlanDay,
        strengthAddOne,
        strengthMove,
        strengthOffload,
        chatNoData,
    ]

    /// The scenario with `id`, if any.
    public static func scenario(id: String) -> EvalScenario? {
        all.first { $0.id == id }
    }

    /// Scenarios matching every filter given. `nil` filters match everything.
    /// - Parameters:
    ///   - ids: Exact scenario ids.
    ///   - tag: A tag the scenario must carry.
    /// - Returns: Matching scenarios in library order.
    public static func select(ids: [String] = [], tag: String? = nil) -> [EvalScenario] {
        all.filter { scenario in
            (ids.isEmpty || ids.contains(scenario.id))
                && (tag.map { scenario.tags.contains($0) } ?? true)
        }
    }

    /// Every tag in use, sorted.
    public static var tags: [String] {
        Set(all.flatMap(\.tags)).sorted()
    }
}
