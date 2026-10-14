# Architecture

## Overview

Hybrid AIthletics uses a flat-layered architecture with SwiftUI + SwiftData. There are no ViewModels — SwiftData's `@Query` macro provides reactive data binding directly in views.

## Layers

```
Packages/AICoachCore/      Shared library: prompt builder, coaching types, formatters, GenerationConfig
Evals/                     AI coach eval CLI (Swift inspect + Python eval runner)
Models/                    @Model classes, enums (data layer)
Config/                    ModelContainer setup, environment keys (infrastructure)
Extensions/                Date arithmetic, formatting (utilities)
Services/                  Protocol-based service layer (AI coach)
Views/                     SwiftUI views grouped by tab (presentation)
```

## Data Models

### Exercise
The single persisted entity — a training activity that is planned, recorded, or both.

- One `date` field (the day planned and/or performed); stored as-is, with day/week grouping via `Date+Week` helpers
- Planned target metrics (`durationSeconds`, `distanceMiles`, `notes`) live on the exercise; recorded actuals live in the nested `workout`
- `workout: Workout?` — embedded recorded-instance data; `nil` = planned only, non-nil = recorded. `isCompleted` is `workout != nil`
- `id: UUID` is explicit for drag-and-drop `Transferable` support and list/navigation identity

### Workout
The recorded-instance data for an `Exercise`. **Not** a `@Model` — a plain `Codable` value `struct` stored inline on `Exercise.workout` (no second table).

- Holds the recorded **actuals**: `durationSeconds`, `distanceMiles`, `notes`, plus `feeling`, `perceivedExertion`, `source`, `externalID`
- Has no date/name/type — those belong to the owning `Exercise`
- `feeling: Int?` (1–5) and `perceivedExertion: Int?` (1–10) — two **independent** subjective ratings, `nil` when unrated. Both feed the AI coach's training-load assessment; a high exertion felt strong is a good session, the same exertion felt weak is an overreaching flag
- `Workout(draftFrom:)` pre-fills a recorded workout's actuals from an exercise's planned targets
- `source` / `externalID` are import-pipeline provenance/dedup metadata

### AppConfiguration
Singleton preferences stored in SwiftData for CloudKit sync.

- `useMetricUnits: Bool` — controls distance display across the app
- Accessed via `@Query` in `ContentView`, propagated as a SwiftUI `EnvironmentKey`

### ExerciseType
`String`-backed enum shared by Exercise and Workout. Provides `systemImage` and `color` computed properties for consistent UI rendering.

## Key Design Decisions

### @Query placement
Only top-level tab views (`AerobicTrainingView`, `HistoryView`) and `ContentView` own `@Query` properties. All child views receive data as plain `let` parameters. This minimizes SwiftData subscription overhead — each `@Query` causes its entire view subtree to re-evaluate on any change to the queried model type.

Both tabs use an **unfiltered** `@Query private var allExercises: [Exercise]` and derive what they need in computed vars: `HistoryView` filters to completed exercises (`workout != nil`) and sorts by `date` descending in memory; `AerobicTrainingView` filters by week. The completed/planned split is done in memory because a `#Predicate` cannot reach into the nested `workout` Codable composite attribute. This is cheap at single-user scale.

### Distance storage
All distances are stored in miles internally. Conversion to display units (km) happens at the view layer using `Double.formattedDistance(metric:)` and `Double.toDisplayDistance(metric:)`. The `useMetricUnits` flag is read from the environment.

### Week boundaries
The app uses Monday as the first day of the week regardless of locale. A private `mondayCalendar` (with `firstWeekday = 2`) is used for all week boundary calculations in `Date+Week.swift`.

### Drag-and-drop
Exercises use a lightweight `ExerciseDragItem` (carrying only a UUID) as the `Transferable` payload. The custom UTType `com.hybridaithletics.exercise` is registered in Info.plist via `UTExportedTypeDeclarations`. The drop handler looks up the exercise by ID and mutates `scheduledDate`. Full model objects are never serialized for drag transfer.

### Repeating exercises
Exercises can be marked as `isRepeating: Bool`. A repeating exercise serves as a template that appears virtually on its matching day-of-week for the current week and all future weeks.

**Virtual display**: `AerobicTrainingView.weekExercises` includes repeating exercises from other weeks whose `date.mondayBasedWeekdayIndex` matches a day in the displayed week, provided no concrete instance (same name + type + day) already exists. Virtual exercises only appear for the current week forward — past weeks show only concrete data.

**On-demand materialization**: When the user interacts with a virtual exercise (record, edit, or drag), `WeeklyCalendarView.materializeIfNeeded` creates a concrete copy with `isRepeating: false` for that specific day. The original template remains unchanged.

**Day matching**: `WeeklyCalendarView.exercisesForDay` matches exercises by `date.isSameDay` (concrete) or `date.mondayBasedWeekdayIndex` (virtual repeating).

### CloudKit sync
Configured via `ModelConfiguration(cloudKitDatabase: .automatic)` in `ModelContainerFactory`. All model properties have default values for CloudKit compatibility. The CloudKit container ID must be registered in the Apple Developer portal and match the entitlements file.

### AICoachCore local package
The `Packages/AICoachCore/` local Swift package is the single source of truth for all coaching logic shared between the iOS app and the eval CLI. It contains:
- **`AICoachPromptBuilder`** — stateless prompt construction with `buildPrompt(for:)` (flat) and `buildUserContent(for:)` (user-only, for use with separate system role)
- **Coaching types** — `CoachWorkout`, `CoachExercise`, `CoachingRequest`, `CoachingResponse` (plain structs, no SwiftData)
- **`CoachExerciseType`** — mirrors the app's `ExerciseType` raw values without UI properties
- **`GenerationConfig`** — all LLM generation parameters (temperature, topP, repetitionPenalty, etc.) with named presets
- **Distance/duration formatters** — internal to the package, used by the prompt builder

The app's SwiftData models are converted to AICoachCore types via `CoachTypeConversions.swift` (`CoachWorkout(from:)`, `CoachExercise(from:)`).

### AI Coach service layer
The on-device coaching feature lives behind a protocol, `AICoachService`, so the rest of the app never imports MLX or any specific runtime directly.

**Protocol and environment injection.** `Services/AICoach/AICoachService.swift` defines `suggestAdaptations(_:)` and `streamSuggestion(_:)`. The service is exposed via `@Environment(\.aiCoach)` (`Config/AICoachEnvironment.swift`). The default environment value is `StubAICoachService`, so SwiftUI previews and unit tests never accidentally load real model weights. The app root (`Hybrid_AIthleticsApp.swift`) replaces the default with an `MLXAICoachService` instance at launch.

**Implementations.**
- `StubAICoachService` — returns a deterministic canned response and streams it in small chunks with artificial delay. Used by previews and tests.
- `MLXAICoachService` — production implementation backed by Gemma 4 E2B via MLX-Swift. The model is downloaded from Hugging Face on first use and cached locally. The actual MLX calls are gated behind `#if canImport(MLXLLM)` so the file compiles even before the SPM dependency is added, throwing `AICoachError.notImplemented` until the dependency is in place. Reads generation parameters from `GenerationConfig.production`. Uses `UserInput(chat:)` with separate system/user roles.

**Prompt construction.** `AICoachPromptBuilder` lives in the `AICoachCore` package and turns a `CoachingRequest` into prompt text. It provides both `buildPrompt(for:)` (flat string) and `buildUserContent(for:)` (user content only, for use alongside `systemPreamble`). Note: Gemma 3's chat template folds system messages into the first user turn regardless, so both approaches produce identical tokenized prompts.

**Request ownership.** The top-level `AerobicTrainingView` assembles the `CoachingRequest` from its own `@Query` data: recent "workouts" are completed exercises (`isCompleted`) in the last 4 weeks, and upcoming exercises are planned-only ones in the next 2 weeks. Conversion to AICoachCore types goes through `CoachWorkout(from: exercise)` (reads `exercise.date`/`type` + the recorded `workout` metrics) and `CoachExercise(from: exercise)`.

### Eval CLI
The `Evals/` directory contains tools for iterating on the AI coach's prompt and generation parameters outside the iOS app:
- **`swift run CoachEval inspect`** — prints the formatted prompt from AICoachCore without running the model
- **`python3 eval_runner.py`** — runs prompts through Python MLX and scores output quality (100-point scale)
- Shares prompt and config via the `AICoachCore` package, so changes propagate to both app and evals

See `Evals/README.md` for full documentation.

### Model delivery
The Gemma 4 E2B 4-bit model is **not bundled** in the app binary. Instead, `MLXAICoachService` uses `ModelConfiguration(id: "lmstudio-community/gemma-4-E2B-it-MLX-4bit")` to download the weights from Hugging Face on first use (~4.3 GB). MLXLLM caches the download in the app's caches directory for offline access on subsequent launches. This keeps the app binary small and eliminates the need for developers to manually download and configure model weights.

## Data Flow

### Adding an exercise
```
AddExerciseSheet → modelContext.insert(Exercise) → SwiftData persists →
CloudKit sync (async) → @Query in AerobicTrainingView fires → UI updates
```

### Recording a workout
```
ExerciseCardView tap → RecordWorkoutSheet (pre-filled from the planned exercise) →
User edits & saves → exercise.workout = Workout(...actuals...) set on the exercise
(quick-add with no plan inserts a new completed Exercise instead) → @Query updates both tabs
```

### Rescheduling via drag-and-drop
```
Drag ExerciseCardView → ExerciseDragItem(UUID) transferred → Drop on target day →
exercise.date = targetDay → SwiftData auto-saves → @Query fires → UI re-renders
```

### Interacting with a virtual repeating exercise
```
User taps record/edit on virtual exercise → materializeIfNeeded creates concrete copy →
concrete Exercise inserted into modelContext → callback receives concrete instance →
sheet opens with concrete exercise → @Query fires → UI shows new concrete + hides virtual
```

### Importing (CSV / Apple Health)
```
Parse rows / fetch HK workouts → map each to ONE completed Exercise
(WorkoutCSV.toExercise / HealthKitWorkoutMapper.toExercise) → modelContext.insert(exercise) →
HealthKit dedups against existing workout.externalID (collected in memory) →
@Query fires → imported activity appears in BOTH History and the training calendar
```

### Requesting AI coaching suggestions
```
User taps "Ask Coach" in AerobicTrainingView → buildCoachRequest() reads recent completed
exercises (last 4 weeks) and upcoming planned exercises (next 2 weeks) from @Query →
exercises converted to AICoachCore types (CoachWorkout, CoachExercise) →
CoachingRequest assembled → AICoachSheet presented → on .task, calls
coach.streamSuggestion(request) → AICoachPromptBuilder serializes request to prompt →
MLXAICoachService builds UserInput(chat:) with system/user roles →
MLX generates response token by token → AICoachSheet appends chunks to responseText → UI updates live
```

### Editing or deleting a recorded workout
```
User taps a row in WorkoutListView → the row's .sheet(item:) presents
WorkoutDetailSheet with the (completed) Exercise → @State fields seed from the
exercise + its workout in init(), distance converts to display units in .onAppear
(since @Environment isn't available during init) → WorkoutFormFields renders the
same form sections RecordWorkoutSheet uses → User edits → Save calls
WorkoutEditor.apply(_:to:), which writes name/type/date onto the exercise and
rebuilds exercise.workout from the edited actuals (preserving source/externalID) →
SwiftData auto-persists → @Query in HistoryView fires → list refreshes → sheet dismisses.

Delete path: Delete Workout button → confirmationAlert → "Delete" tapped →
performDelete() calls modelContext.delete(exercise) then modelContext.save() to
flush before @Query re-evaluates → dismiss. Under the `-uiTestSeed` launch
argument, the alert is bypassed because SwiftUI's nested alert button
structure is not reliably driveable via XCUIApplication — UI tests call
performDelete() directly, and the alert's functional correctness is covered
by unit tests over WorkoutEditor + modelContext.delete.
```

### Navigating from calendar to workout list
```
User taps a calendar day with workouts → MonthlyCalendarView invokes
onDayTap(day) → HistoryView resolves the first (most-recent) completed
exercise for that day from its derived `completedExercises` and constructs a fresh
WorkoutNavigationRequest(workoutID:) (carrying the Exercise.id; new UUID id per
tap so repeat taps still fire .onChange) → WorkoutListView.onChange computes the target page
index via WorkoutListPagination.pageIndex(forItemAt:pageSize:), animates
currentPage, sets highlightedID → ~2.5s later, a background Task clears
highlightedID with an ease-in-out animation.
```

## Testing

Unit tests cover:
- **Models**: Exercise persistence, the nested `workout` Codable composite attribute round-tripping through SwiftData, `isCompleted` / completed-vs-planned in-memory filtering, `Workout(draftFrom:)`, repeat flag, felt-rating default and persistence
- **Extensions**: date arithmetic (week boundaries, month boundaries, same-day/week/month checks), distance formatting, duration formatting, **pace formatting** (metric/imperial, zero-distance fallback, truncation behavior)
- **Types**: ExerciseType codable round-trip, identifiable conformance
- **Drag items**: ExerciseDragItem codable round-trip
- **Repeat**: isRepeating default value, init parameter, persistence, day-of-week matching
- **AI Coach**: type conversion tests (SwiftData → AICoachCore), `StubAICoachService` response and streaming
- **AICoachCore package tests** (separate target): prompt builder formatting (RPE and feeling inclusion/omission, notes handling, unit respect, ordering, empty inputs), distance/duration formatting, generation config codable round-trip
- **Workout list pagination**: pure-math helpers in `WorkoutListPagination` (page index boundaries, total page counts, empty-state handling)
- **Workout detail edit**: `WorkoutEditor.apply(_:to:)` rewrites the exercise's identity fields and rebuilds the nested `workout` from edited actuals, preserves import metadata (`source`, `externalID`), and `modelContext.delete(exercise)` scopes correctly

App tests use `ModelContainerFactory.makePreviewContainer()` for isolated in-memory SwiftData contexts. Tests that touch a context should construct a detached `ModelContext(container)` rather than using `container.mainContext`, which is `@MainActor`-isolated and crashes under Swift Testing's parallel execution. The MLX-backed coach is never exercised in unit tests — all coach tests run against `StubAICoachService`. Prompt builder tests live in the `AICoachCore` package and use plain structs, not SwiftData models.

### Functional UI tests

`Hybrid AIthleticsUITests/HistoryUITests.swift` (XCTest + `XCUIApplication`; Swift Testing doesn't integrate with XCUI) validates the History tab end-to-end:

- First-page rendering (10 rows), prev/next button enablement at page boundaries
- Forward/backward page navigation via `workoutList.prevPage` / `workoutList.nextPage` identifiers
- Last-page disable behavior and partial-page rendering
- Calendar day tap → workout list focus (tap-today keeps page 1 and highlights the row)
- Workout row tap → `WorkoutDetailSheet` presents with the shared form fields
- Edit flow: mutate name → save → row label updates
- Delete flow: tap Delete Workout → row removed → pagination clamp

Tests launch the app with `-uiTestSeed` which switches to `makePreviewContainer()` (no CloudKit, no persistent state) and seeds 25 deterministic workouts via `Config/UITestFixtures.swift`. This gives 3 pages at 10 per page, enough to exercise all pagination boundaries. Rows and controls carry stable `.accessibilityIdentifier` strings (`workoutRow.<uuid>`, `workoutList.pageLabel`, `workoutForm.nameField`, `workoutDetail.saveButton`, `workoutDetail.deleteButton`, `calendarDay.yyyy-MM-dd`). The delete path's confirmation alert is bypassed in UI test mode because SwiftUI's nested alert button tree breaks XCUI automation — the alert is still shown to real users, and its functional correctness is covered by unit tests over `WorkoutEditor`.
