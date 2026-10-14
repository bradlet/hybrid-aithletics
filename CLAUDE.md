# CLAUDE.md

## Project
Hybrid AIthletics — iOS exercise tracking app (SwiftUI + SwiftData + CloudKit).

## Build & Test
```bash
# Build app
xcodebuild -scheme "Hybrid AIthletics" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' build

# Run app unit tests
xcodebuild test -scheme "Hybrid AIthletics" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Hybrid AIthleticsTests"

# Run History tab functional UI tests
xcodebuild test -scheme "Hybrid AIthletics" -destination 'platform=iOS Simulator,name=iPhone 17 Pro' -only-testing:"Hybrid AIthleticsUITests/HistoryUITests"

# Run AICoachCore package tests
cd Packages/AICoachCore && swift test

# Run AI coach evals (requires pip3 install mlx-lm)
cd Evals && python3 eval_runner.py

# Inspect AI coach prompts (no model needed)
cd Evals && swift run CoachEval inspect --scenario high-rpe --prompt-mode chat
```

## Architecture
- **No ViewModels** — `@Query` in top-level views only (`HomeView`, `AerobicTrainingView`, `HistoryView`, `ContentView`). Child views receive data as `let` parameters. App-scope observable state that isn't a ViewModel (owns no queries, makes no view decisions) is a `@MainActor @Observable` service injected via `@Environment` — see `GoogleSheetsSyncCoordinator` and `CoachChatStore`.
- **Models**: `Exercise` (planned), `Workout` (recorded), `AppConfiguration` (preferences), `ExerciseType` (enum)
- **Distance storage**: Always miles internally. Display conversion via `Double.formattedDistance(metric:)`. Unit preference via `@Environment(\.useMetricUnits)`.
- **Week start**: Monthly calendar grids are always Sunday-first — standard `Calendar.current` week (see `Date+Week.swift`). The user's `AppConfiguration.weekStartDay` (1=Sun…7=Sat, injected via `@Environment(\.weekStartDay)`) governs (a) weekly *aggregation* (mileage buckets, "This Week" stats — threaded into `WorkoutAggregations` as `firstWeekday`) and (b) the Aerobic Training *weekly* calendar: its day ordering, week boundaries, navigation, and header mileage totals use the `firstWeekday:` variants (`daysInWeek(firstWeekday:)`, `startOfWeek(firstWeekday:)`, `endOfWeek(firstWeekday:)`) so the topmost swimlane is the configured week start. The no-arg Sunday-first helpers remain for monthly views and must not change.
- **CloudKit**: All model properties must have default values for CloudKit compatibility.
- **Activity opted out of training progress is visually distinct.** `Exercise.countsTowardMileage == false` surfaces as a hollow calendar dot (via `CalendarDisplayable.countsTowardTraining` → `CalendarDayDot`) and a dimmed History row carrying a "Not training" badge. A day mixing counted and opted-out activity still draws a solid dot — it *was* a training day.
- **Feeling and perceived exertion are two independent fields**, never one. `Workout.feeling` is 1–5 (Very Weak → Very Strong) and `Workout.perceivedExertion` is RPE 1–10; both are `Int?` with `nil` meaning "not recorded". The AI coach prompt emits each verbatim and omits it when `nil` — there is no inversion or derivation between them (there used to be, and it was wrong). Charts of feeling must plot `nil` as a **gap**, never as `0`.
- **Enums in @Model classes** must be plain raw-value Codable enums (like `ExerciseType`). An enum with a custom `init(from:)` (e.g. `MuscleGroup`'s tolerant decode) makes SwiftData treat it as a composite Codable attribute and its encoder crashes on save — store the raw String instead and expose a computed enum property (see `StrengthExercise.muscleGroupRaw`, `Workout.source`).
- **AICoachCore local package**: `Packages/AICoachCore/` — shared library containing prompt builder, coaching types (`CoachWorkout`, `CoachExercise`, `CoachingRequest`, `CoachingResponse`), formatters, and `GenerationConfig`. Used by both the iOS app and the `Evals/` CLI. The app converts SwiftData models to AICoachCore types via `CoachTypeConversions.swift`.
- **AI Coach service layer**: `AICoachService` protocol with two implementations — `MLXAICoachService` (production, Gemma 4 E2B via MLX-Swift) and `StubAICoachService` (previews/tests/UI tests). Injected via `@Environment(\.aiCoach)`. Default environment value is the stub so previews never load real models. Uses `UserInput(chat:)` with separate system/user roles for proper chat template formatting. The app root injects the stub under `-uiTestSeed` so UI tests never trigger the model download.
- **The coach is tool-calling.** `streamChat` yields `CoachEvent`s (`.textChunk` / `.action` / `.rejectedToolCall`), mirroring the runtime's `Generation` cases so no app code outside `Services/AICoach/` imports MLX. Three tools live in `CoachToolSchemas`: `chat`, `suggest_schedule_change`, `record_workout`. **The mutating tools propose, never write** — a tool call becomes a pending proposal the athlete accepts, applied via `CoachProposalApplier` (schedule changes) or a pre-filled `RecordWorkoutSheet` (workouts). Decode and validate through `CoachToolDecoder`, **not** the runtime's `ToolCall.execute(with:)`, whose hardcoded `JSONDecoder` can't parse a model-emitted `"2026-04-06"`. Out-of-range ratings are rejected, never clamped.
- **AI model delivery**: Gemma 4 E2B 4-bit weights (~4.3 GB) are **not bundled** — they download from Hugging Face on first use and are cached locally for offline access. mlx-swift-lm 3.x dropped its bundled Hub integration, so `Services/AICoach/MLXModelLoading.swift` supplies the `Downloader` / `TokenizerLoader` conformances over swift-transformers' `HubApi` and `AutoTokenizer`, plus an adapter bridging its `Tokenizer` to `MLXLMCommon`'s own copy. `ModelConfiguration.toolCallFormat` and `extraEOSTokens` must match the model family (`.gemma4` + `<turn|>` today; Gemma 3 used `.gemma` + `<end_of_turn>`). Note `Evals/` still pins Gemma 3 4B, so eval scores no longer reflect the production model.
- **Conditional compilation**: All MLX-specific code is gated behind `#if canImport(MLXLLM)`. The `#else` branches throw `AICoachError.notImplemented` so the app compiles on simulators/CI without the SPM dependency resolved.
- **Google Sheets Sync**: `GoogleSheetsSyncCoordinator` (`@MainActor @Observable`) debounces workout mutations and exports via the `GoogleSheetsAPI` protocol (`LiveGoogleSheetsAPI` uses GoogleSignIn-iOS + URLSession behind `#if canImport(GoogleSignIn)`; `StubGoogleSheetsAPI` for previews/tests). Injected via `@Environment(\.googleSheetsSync)`. Uses the **`auth/drive.file` scope** (per-file access only — non-sensitive, no Google verification needed); never `auth/spreadsheets`. OAuth client + Info.plist setup is documented in README.

## Testing Requirements

**Every new feature must ship with unit tests. This is non-negotiable.**

- New model fields → test default value, explicit set, and SwiftData persistence.
- New service/logic types → test all public methods and edge cases (empty inputs, boundary values).
- New prompt/serialization logic → test each output field, metric/imperial variants, omission conditions.
- Prompt builder tests live in `Packages/AICoachCore/Tests/AICoachCoreTests/PromptBuilderTests.swift`.
- App-level tests live in `Hybrid AIthleticsTests/Hybrid_AIthleticsTests.swift`, grouped by `struct` with a `// MARK:` header.
- Functional UI tests for multi-step flows live in `Hybrid AIthleticsUITests/` using `XCTest` + `XCUIApplication` (UI tests stay on XCTest because Swift Testing doesn't integrate with XCUI). They launch the app with `-uiTestSeed` to install an in-memory container + deterministic fixtures via `Config/UITestFixtures.swift`. Add new identifiers via `.accessibilityIdentifier(...)` when introducing testable controls.
- SwiftData tests that touch a `ModelContext` should use `ModelContext(container)` rather than `container.mainContext` — `mainContext` is `@MainActor`-isolated and crashes under Swift Testing's parallel execution.
- Do not ship a feature without at least one test per public method.

## Conventions
- Swift Testing framework (not XCTest) — use `@Test`, `#expect()`, `import Testing`
- Header doc comments on all public/internal functions
- `ModelContainerFactory.makePreviewContainer()` for test and preview contexts
- Cached `DateFormatter` instances (static lets) — never allocate in computed properties
- **The strength board never changes the selected day in response to a move.** Dragging a card onto a day chip and the card's "Move to Day" context menu both leave `selectedDay` alone; the chip counts are the feedback. Don't "helpfully" follow the exercise.
- **Plan editing goes through `StrengthPlanFields`/`StrengthPlanDraft`.** Any surface that sets `plannedSets`/`plannedReps` (add-from-library today) reuses that section so the add and edit flows can't drift apart.
- **Sheets sync `syncNow()` vs `performSync()` must stay split.** The debounce `Task` calls `performSync()` directly. Calling `syncNow()` from inside the debounce task would `.cancel()` the task on itself, propagating cancellation to the in-flight `URLSession` and surfacing as `CancellationError("cancelled")`. `StubGoogleSheetsAPI.overwriteSheet` calls `Task.checkCancellation()` to catch regressions of this pattern.

## File Layout
```
Packages/
  AICoachCore/   Shared library: prompt builder, coaching types, formatters, GenerationConfig
Evals/           AI coach eval CLI + Python eval runner
Models/          Data models and enums
Config/          ModelContainer, environment keys (units, aiCoach), UITestFixtures
Extensions/      Date+Week, Double+Distance (distance, duration, pace formatting)
Services/
  AICoach/       Protocol, MLX implementation, stub, type conversions
Views/
  Home/             Home tab (today's training, quick record, coach chat)
  AerobicTraining/  Training tab
  History/          History tab (calendar, workout list, detail sheet)
  Strength/         Strength tab
  Shared/           Cross-tab building blocks (e.g. WorkoutFormFields)
```

## Key Files
- `Packages/AICoachCore/Sources/AICoachCore/AICoachPromptBuilder.swift` — stateless prompt serialization (shared by app + evals)
- `Packages/AICoachCore/Sources/AICoachCore/GenerationConfig.swift` — single source of truth for LLM generation parameters
- `Config/ModelContainerFactory.swift` — single place for container/CloudKit config
- `Config/AICoachEnvironment.swift` — `@Environment(\.aiCoach)` key; default is `StubAICoachService`
- `Config/UITestFixtures.swift` — deterministic fixture seed activated by `-uiTestSeed` launch arg
- `Extensions/Date+Week.swift` — all calendar arithmetic
- `Extensions/Double+Distance.swift` — distance, duration, and pace formatting (`Int.formattedPace(distanceMiles:metric:)` for min/mile and min/km)
- `Models/ExerciseType.swift` — exercise type enum with icons and colors
- `Models/ExerciseSeriesSpec.swift` — Codable spec for a recurring exercise series (cadence, inclusive end date, every-N-occurrences progression)
- `Services/ExercisePlanner/SeriesGenerator.swift` — pure spec → dated occurrences expansion (monthly anchored to start date, 400-occurrence cap)
- `Services/ExercisePlanner/ExercisePlanner.swift` — bulk CRUD for series-tagged exercises (`seriesID`). Scoped to *series* mutations; a coach proposal targets one session on one day and so mutates it directly via `CoachProposalApplier` (which calls `detach` before removing a series member). Recurring plans are eager bulk inserts of concrete `Exercise` rows — there are no templates or virtual instances.
- `Services/AICoach/AICoachService.swift` — protocol + `AICoachError` enum
- `Services/AICoach/MLXAICoachService.swift` — production coach; swap model via `modelID` constant
- `Services/AICoach/MLXModelLoading.swift` — Hugging Face downloader, tokenizer loader, and tokenizer adapter for mlx-swift-lm 3.x
- `Services/AICoach/CoachChatStore.swift` — ephemeral (session-scoped) conversation state; `@Environment(\.coachChat)`
- `Services/AICoach/CoachProposalApplier.swift` — applies accepted proposals; typed failures, no invented sessions (unit-tested)
- `Services/AICoach/CoachTypeConversions.swift` — SwiftData ↔ AICoachCore type bridge
- `Packages/AICoachCore/Sources/AICoachCore/CoachTools.swift` — tool vocabulary + proposal payloads
- `Packages/AICoachCore/Sources/AICoachCore/CoachToolSchemas.swift` — JSON schemas (no MLX import)
- `Packages/AICoachCore/Sources/AICoachCore/CoachToolDecoding.swift` — validating decoder for raw tool calls
- `Views/Home/HomeView.swift` — Home tab; owns the queries and builds the coach's training snapshot
- `Views/Home/TodayTraining.swift` — pure day selection for Home (unit-tested)
- `Views/Home/CoachChatView.swift` — the conversation: bubbles, composer, proposal cards
- `Services/GoogleSheetsSync/GoogleSheetsSyncCoordinator.swift` — debounce + lifecycle + `GoogleSheetsSyncStatus` enum
- `Services/GoogleSheetsSync/GoogleSheetsAPI.swift` — protocol + Live (GoogleSignIn + URLSession) + Stub implementations
- `Views/Shared/WorkoutFormFields.swift` — reusable workout form sections shared by `RecordWorkoutSheet` (create) and `WorkoutDetailSheet` (edit)
- `Views/Shared/RadialRatingPicker.swift` — the radial dial, plus the configured `FeelingDial` (1–5, faces) and `ExertionDial` (1–10, numerals)
- `Views/Shared/RadialDialGeometry.swift` — pure drag → position → snapped-slot math for the dial (unit-tested)
- `Views/Shared/RatingVisuals.swift` — `FeelingVisuals` / `ExertionVisuals`: display names, face symbols, and the two tint ramps
- `Views/History/WeeklyChartSegments.swift` — splits weekly points into contiguous runs so the chart line breaks across weeks with no data (unit-tested)
- `Views/History/CalendarDayDot.swift` — resolves a calendar day's dot to none/solid/hollow from its items' `countsTowardTraining` (unit-tested)
- `Views/History/WorkoutDetailSheet.swift` — edit + delete popup for a recorded workout; contains the `WorkoutEditor` helper enum that owns the mutation path (unit-tested)
- `Views/History/WorkoutListView.swift` — discrete 10-per-page pagination, tappable rows, calendar-driven navigation/highlight, `WorkoutListPagination` helper for testable page math
- `Views/Strength/StrengthBoardPlanner.swift` — pure lane/order mutations for the weekly kanban board (unit-tested)
- `Views/Strength/StrengthPlanFields.swift` — `StrengthPlanDraft` (plan form state + `apply(to:)`) and the shared sets × reps form section used by both the add-from-library and edit-plan flows
- `Views/Strength/ExerciseLibrarySheet.swift` — library browser: muscle-group filter chips + search + sectioned list, plus the `ExerciseLibraryFilter` helper enum owning the filter/grouping math (unit-tested)
