//
//  CoachChatEnvironment.swift
//  Hybrid AIthletics
//
//  SwiftUI environment key that injects the shared `CoachChatStore`.
//  The default value is a fresh, empty store so previews and tests each get
//  their own conversation; the app-scope instance is injected at the root.
//

import SwiftUI

/// Environment key for the shared `CoachChatStore` instance.
private struct CoachChatKey: EnvironmentKey {
    @MainActor
    static let defaultValue = CoachChatStore()
}

extension EnvironmentValues {
    /// The active coach conversation. Defaults to an empty store; the
    /// app-scope instance is injected at the app root so the transcript
    /// survives tab switches and navigation pops.
    var coachChat: CoachChatStore {
        get { self[CoachChatKey.self] }
        set { self[CoachChatKey.self] = newValue }
    }
}
