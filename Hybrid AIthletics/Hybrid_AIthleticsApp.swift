//
//  Hybrid_AIthleticsApp.swift
//  Hybrid AIthletics
//
//  App entry point. Configures the SwiftData model container
//  and injects it into the view hierarchy.
//

import SwiftUI
import SwiftData
#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct Hybrid_AIthleticsApp: App {
    var sharedModelContainer: ModelContainer = Self.makeContainerForLaunch()

    /// Shared on-device coach instance. Uses MLX-Swift to download and run
    /// Gemma 3 4B on-device. The model is downloaded from Hugging Face on
    /// first use and cached locally for offline access. When the MLX-Swift
    /// package is not available, invocations throw `AICoachError.notImplemented`.
    ///
    /// Under `-uiTestSeed` this is the stub instead: a UI test must never
    /// trigger the ~2 GB model download, and the stub's scripted replies are
    /// what make the chat assertions deterministic.
    private let aiCoach: AICoachService = Self.makeCoachForLaunch()

    /// Shared HealthKit import service. Backed by a real `HKHealthStore`,
    /// used by the History tab's "Import from Apple Health" flow.
    private let healthKitImport: HealthKitImportService = LiveHealthKitImportService()

    /// Shared Google Sheets sync coordinator. When the GoogleSignIn SPM
    /// package is not installed, the live API is a throwing stub and the
    /// coordinator surfaces `.notImplemented` errors when the user tries
    /// to enable sync.
    @State private var sheetsSync = GoogleSheetsSyncCoordinator(api: LiveGoogleSheetsAPI())

    /// The coach conversation for this app session. App-scope so the transcript
    /// survives tab switches and navigation pops; deliberately not persisted,
    /// so it starts fresh on every launch.
    @State private var coachChat = CoachChatStore()

    init() {
        // When launched by the UI test harness with `-uiTestSeed`, replace any
        // existing workouts in the container with a deterministic fixture set.
        // This runs against the same `sharedModelContainer` the view hierarchy
        // will use (preview container when seeded — see makeContainerForLaunch).
        if CommandLine.arguments.contains("-uiTestSeed") {
            UITestFixtures.seed(into: sharedModelContainer)
        }
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environment(\.aiCoach, aiCoach)
                .environment(\.healthKitImport, healthKitImport)
                .environment(\.googleSheetsSync, sheetsSync)
                .environment(\.coachChat, coachChat)
                .task {
                    // Restore Google Sheets sync state from AppConfiguration
                    // and silently re-authorize the OAuth session if a
                    // previous sign-in is cached on this device.
                    await sheetsSync.attach(modelContainer: sharedModelContainer)
                }
                #if canImport(GoogleSignIn)
                .onOpenURL { url in
                    // OAuth redirect callback. The reversed-client-ID URL
                    // scheme registered in Info.plist routes here after
                    // the user completes Google sign-in.
                    GIDSignIn.sharedInstance.handle(url)
                }
                #endif
        }
        .modelContainer(sharedModelContainer)
    }

    /// Returns the coach service to inject, honoring the UI test harness.
    private static func makeCoachForLaunch() -> AICoachService {
        if CommandLine.arguments.contains("-uiTestSeed") {
            return StubAICoachService()
        }
        return MLXAICoachService()
    }

    /// Builds the model container to install into the view hierarchy.
    /// - Normally returns `ModelContainerFactory.makeContainer()` (on-disk + CloudKit).
    /// - When launched with `-uiTestSeed`, returns an in-memory preview container
    ///   so UI tests get a clean, deterministic state that never touches CloudKit.
    private static func makeContainerForLaunch() -> ModelContainer {
        if CommandLine.arguments.contains("-uiTestSeed") {
            return ModelContainerFactory.makePreviewContainer()
        }
        return ModelContainerFactory.makeContainer()
    }
}
