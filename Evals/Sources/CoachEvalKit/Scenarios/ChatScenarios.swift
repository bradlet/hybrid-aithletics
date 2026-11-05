//
//  ChatScenarios.swift
//  CoachEvalKit
//
//  Conversation with no action to take.
//

import Foundation
import AICoachCore

extension ScenarioLibrary {

    /// Nothing recorded: the coach should say so plainly rather than invent a
    /// week, and has nothing to propose.
    public static let chatNoData = EvalScenario(
        id: "chat-no-data",
        title: "Admit there is no data",
        summary: "Empty snapshot. Expect a short reply with no proposal and no " +
            "invented workouts.",
        tags: ["chat"],
        snapshot: Fixtures.empty,
        athleteMessage: "How did last week go?",
        expectations: [
            .noProposal,
            .replyNotEmpty,
            .replyOmits(["tempo", "interval", "long run", "miles"]),
            .maxWords(150),
            .noRejections,
        ]
    )
}
