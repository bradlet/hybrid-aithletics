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
Services/                  Protocol-based services (AI coach, exercise planner, exercise library,
                           Google Sheets sync, HealthKit import, CSV)
Views/                     SwiftUI views grouped by tab: Home, AerobicTraining, Strength, History,
                           Settings, plus Shared building blocks (presentation)
```

## Data Models

### Exercise
The single persisted entity — a training activity that is planned, recorded, or both.

- One `date` field (the day planned and/or performed); stored as-is, with day/week grouping via `Date+Week` helpers
- Planned target metrics (`durationSeconds`, `distanceMiles`, `notes`) live on the exercise; recorded actuals live in the nested `workout`
- `workout: Workout?` — embedded recorded-instance data; `nil` = planned only, non-nil = recorded. `isCompleted` is `workout != nil`
- `id: UUID` is explicit for drag-and-drop `Transferable` support and list/navigation identity
- `seriesID: UUID?` — shared by exercises bulk-created as one recurring series (see [Recurring exercise series](#recurring-exercise-series)); `nil` for one-off sessions
- `countsTowardMileage: Bool` — `false` opts the activity out of mileage/training aggregates; it renders as a hollow calendar dot and a dimmed "Not training" History row

### Workout
The recorded-instance data for an `Exercise`. **Not** a `@Model` — a plain `Codable` value `struct` JSON-encoded into the exercise's private `workoutData: Data?` column and exposed as `Exercise.workout` (no second table; a `Workout?` composite attribute would crash SwiftData's decoder on fetch).

- Holds the recorded **actuals**: `durationSeconds`, `distanceMiles`, `notes`, plus `feeling`, `perceivedExertion`, `source`, `externalID`
- Has no date/name/type — those belong to the owning `Exercise`
- `feeling: Int?` (1–5) and `perceivedExertion: Int?` (1–10) — two **independent** subjective ratings, `nil` when unrated. Both feed the AI coach's training-load assessment; a high exertion felt strong is a good session, the same exertion felt weak is an overreaching flag
- `Workout(draftFrom:)` pre-fills a recorded workout's actuals from an exercise's planned targets
- `source` / `externalID` are import-pipeline provenance/dedup metadata

### AppConfiguration
Singleton preferences stored in SwiftData for CloudKit sync.

- `useMetricUnits: Bool` — controls distance display across the app (`@Environment(\.useMetricUnits)`)
- `weekStartDay: Int` — 1 = Sunday … 7 = Saturday; governs weekly aggregation and the Aerobic Training weekly calendar (`@Environment(\.weekStartDay)`)
- `googleSheetsSyncEnabled` / `googleSheetsSpreadsheetID` — Google Sheets export state
- Accessed via `@Query` in `ContentView` (and `SettingsView` for editing), propagated as SwiftUI `EnvironmentKey`s

### ExerciseType
`String`-backed enum used by `Exercise`. Provides `systemImage` and `color` computed properties for consistent UI rendering.

### FavoriteWorkout
A saved aerobic preset (name, type, distance, duration, counts-toward-mileage) with a manual `sortOrder`. Managed from the Home Favorites card; picked from a Home chip (quick-record today) or the "Start from Favorite" menu atop a blank `RecordWorkoutSheet` or create-mode `AddExerciseSheet`. See [DATA_MODEL.md](DATA_MODEL.md#favoriteworkout).

### Strength models
`StrengthExercise` (a card on the weekly strength board), `StrengthWorkout` (a recorded lift), and `UserLibraryExercise` (athlete-created library entries) are documented in [STRENGTH_TRAINING.md](STRENGTH_TRAINING.md).

## Key Design Decisions

### @Query placement
Only top-level views own `@Query` properties: the tab roots (`HomeView`, `AerobicTrainingView`, `StrengthTrainingView`, `HistoryView`), `ContentView`, and `SettingsView`. All child views receive data as plain `let` parameters. This minimizes SwiftData subscription overhead — each `@Query` causes its entire view subtree to re-evaluate on any change to the queried model type.

The exercise-reading views use an **unfiltered** `@Query private var allExercises: [Exercise]` and derive what they need in computed vars: `HistoryView` filters to completed exercises (`workout != nil`) and sorts by `date` descending in memory; `AerobicTrainingView` filters by week. The completed/planned split is done in memory because a `#Predicate` cannot reach inside the JSON-encoded `workoutData` blob that backs `workout`. This is cheap at single-user scale.

### Distance storage
All distances are stored in miles internally. Conversion to display units (km) happens at the view layer using `Double.formattedDistance(metric:)` and `Double.toDisplayDistance(metric:)`. The `useMetricUnits` flag is read from the environment.

### Week boundaries
All calendar arithmetic lives in `Date+Week.swift`. Two week conventions coexist:

- **Monthly calendar grids are always Sunday-first** (the standard `Calendar.current` week), via the no-arg helpers.
- **The user's `AppConfiguration.weekStartDay`** governs weekly *aggregation* (mileage buckets, "This Week" stats — passed into `WorkoutAggregations` as `firstWeekday`) and the Aerobic Training *weekly* calendar (day order, week boundaries, navigation, header totals) via the `firstWeekday:` variants (`daysInWeek(firstWeekday:)`, `startOfWeek(firstWeekday:)`, `endOfWeek(firstWeekday:)`).

### Drag-and-drop
Exercises use a lightweight `ExerciseDragItem` (carrying only a UUID) as the `Transferable` payload. The custom UTType `com.hybridaithletics.exercise` is registered in Info.plist via `UTExportedTypeDeclarations`. The drop handler (`WeeklyCalendarView`) looks up the exercise by ID and sets its `date` to the target day. Full model objects are never serialized for drag transfer.

### Recurring exercise series
Recurring plans are **eager bulk inserts of concrete `Exercise` rows** — there are no templates and no virtual instances.

- `ExerciseSeriesSpec` (Codable) describes the series: cadence, inclusive end date, and an every-N-occurrences progression.
- `SeriesGenerator.occurrences(for:)` is a pure spec → dated occurrences expansion (monthly cadence anchored to the start date, capped at 400 occurrences).
- `ExercisePlanner` is the bulk CRUD surface keyed on `seriesID`: `createSeries`, `members(of:scope:)`, `updateSeries`, `deleteSeries`, and `detach` (removes one exercise from its series so it can be edited or deleted on its own).
- The AI coach's proposals target a single session, so `CoachProposalApplier` mutates that one exercise directly (calling `detach` before removing a series member) rather than going through the series API.

### CloudKit sync
Configured via `ModelConfiguration(cloudKitDatabase: .automatic)` in `ModelContainerFactory`. All model properties have default values for CloudKit compatibility. The CloudKit container ID must be registered in the Apple Developer portal and match the entitlements file.

### AI coach
The on-device, tool-calling AI coach (Gemma 4 E2B via MLX-Swift, reached from the Home tab) has its own contributor guide: **[AI_COACH.md](AI_COACH.md)**. In brief:

- **`Packages/AICoachCore/`** is a pure-Swift local package (no MLX, no SwiftData) shared by the app and the `Evals/` CLI: coaching snapshot types, `AICoachPromptBuilder`, the tool vocabulary (`CoachTools`), JSON schemas (`CoachToolSchemas`), the validating `CoachToolDecoder`, and `GenerationConfig`.
- **`Services/AICoach/`** holds the `AICoachService` protocol (`MLXAICoachService` in production, `StubAICoachService` for previews/tests, injected via `@Environment(\.aiCoach)` with the stub as default), the app-scope `CoachChatStore` (`@Environment(\.coachChat)`), the Hugging Face downloader, `CoachProposalApplier`, SwiftData ↔ core conversions, and speech-to-text.
- **The coach proposes, never writes.** Every mutating tool call becomes an Accept/Dismiss card; `HomeView` applies accepted proposals.
- **Model delivery:** the ~4.3 GB weights are not bundled. They download from Hugging Face only when the athlete taps Download in the chat, with byte-weighted progress, and are cached for offline use.

### Eval CLI
The `Evals/` directory contains tools for iterating on the AI coach's prompt outside the iOS app:
- **`swift run CoachEval inspect --prompt-mode flat|chat|conversation`** — prints the prompt from AICoachCore without running a model (`conversation` shows the tool-calling chat turns and tool schemas the app sends)
- **`python3 eval_runner.py`** — runs the one-shot prompt through Python MLX and scores output quality (100-point scale). It still pins Gemma 3 4B, so scores do not reflect the production model.

See `Evals/README.md` for full documentation.

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

### Creating a recurring series
```
AddExerciseSheet (repeat options) → ExerciseSeriesSpec → SeriesGenerator.occurrences(for:) →
ExercisePlanner.createSeries inserts one concrete Exercise per occurrence, all sharing a seriesID →
@Query fires → every occurrence appears on its own day
```

### Importing (CSV / Apple Health)
```
Parse rows / fetch HK workouts → map each to ONE completed Exercise
(WorkoutCSV.toExercise / HealthKitWorkoutMapper.toExercise) → modelContext.insert(exercise) →
HealthKit dedups against existing workout.externalID (collected in memory) →
@Query fires → imported activity appears in BOTH History and the training calendar
```

### Talking to the AI coach
```
Home coach card / mic → CoachChatView → (first open) CoachChatStore.prepareModel loads cached
weights, or shows the Download call to action → athlete sends a message →
CoachChatStore.send attaches HomeView.buildCoachRequest() (last 4 weeks of completed exercises,
next 2 weeks of planned ones, the strength board) on the first turn only →
MLXAICoachService.streamChat builds chat turns + tool schemas (today's date in both) →
MLX generates → text streams into the coach bubble; tool calls are validated by
CoachToolDecoder and surface as proposal cards → Accept → HomeView applies via
CoachProposalApplier (or opens a pre-filled RecordWorkoutSheet) → @Query fires → UI updates
```
See [AI_COACH.md](AI_COACH.md) for the full sequence.

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
- **Models**: Exercise persistence, the nested `workout` (JSON-encoded into `workoutData`) round-tripping through SwiftData, `isCompleted` / completed-vs-planned in-memory filtering, `Workout(draftFrom:)`, `feeling` / `perceivedExertion` defaults and persistence, `seriesID` and `countsTowardMileage`
- **Extensions**: date arithmetic (week boundaries, month boundaries, same-day/week/month checks), distance formatting, duration formatting, **pace formatting** (metric/imperial, zero-distance fallback, truncation behavior)
- **Types**: ExerciseType codable round-trip, identifiable conformance
- **Drag items**: ExerciseDragItem codable round-trip
- **Series**: `SeriesGenerator` expansion (cadences, end dates, progression, occurrence cap) and `ExercisePlanner` bulk create/update/delete/detach
- **AI Coach**: type conversions (SwiftData → AICoachCore), `StubAICoachService`, `CoachChatStore`, `CoachProposalApplier`, download progress and byte-rate math, voice draft merging — see [AI_COACH.md](AI_COACH.md#15-testing)
- **AICoachCore package tests** (separate target): prompt builder formatting (RPE and feeling inclusion/omission, notes handling, unit respect, ordering, empty inputs, strength section), chat turns and date anchor, tool schemas, tool-call decoding and every rejection path, distance/duration formatting, generation config codable round-trip
- **Workout list pagination**: pure-math helpers in `WorkoutListPagination` (page index boundaries, total page counts, empty-state handling)
- **Workout detail edit**: `WorkoutEditor.apply(_:to:)` rewrites the exercise's identity fields and rebuilds the nested `workout` from edited actuals, preserves import metadata (`source`, `externalID`), and `modelContext.delete(exercise)` scopes correctly

App tests use `ModelContainerFactory.makePreviewContainer()` for isolated in-memory SwiftData contexts. Tests that touch a context should construct a detached `ModelContext(container)` rather than using `container.mainContext`, which is `@MainActor`-isolated and crashes under Swift Testing's parallel execution. The MLX-backed coach is never exercised in unit tests — all coach tests run against `StubAICoachService`. Prompt builder tests live in the `AICoachCore` package and use plain structs, not SwiftData models.

### Functional UI tests

Functional UI tests live in `Hybrid AIthleticsUITests/` (XCTest + `XCUIApplication`; Swift Testing doesn't integrate with XCUI): `HomeUITests` (Home tab, coach chat, proposals, voice entry, model download flow — run with `-uiTestCoachNotDownloaded` for the download cases), `AerobicTrainingUITests`, `StrengthLibraryUITests`, `RatingPickerUITests`, and `HistoryUITests`.

`HistoryUITests.swift` validates the History tab end-to-end:

- First-page rendering (10 rows), prev/next button enablement at page boundaries
- Forward/backward page navigation via `workoutList.prevPage` / `workoutList.nextPage` identifiers
- Last-page disable behavior and partial-page rendering
- Calendar day tap → workout list focus (tap-today keeps page 1 and highlights the row)
- Workout row tap → `WorkoutDetailSheet` presents with the shared form fields
- Edit flow: mutate name → save → row label updates
- Delete flow: tap Delete Workout → row removed → pagination clamp

Tests launch the app with `-uiTestSeed` which switches to `makePreviewContainer()` (no CloudKit, no persistent state) and seeds 25 deterministic workouts via `Config/UITestFixtures.swift`. This gives 3 pages at 10 per page, enough to exercise all pagination boundaries. Rows and controls carry stable `.accessibilityIdentifier` strings (`workoutRow.<uuid>`, `workoutList.pageLabel`, `workoutForm.nameField`, `workoutDetail.saveButton`, `workoutDetail.deleteButton`, `calendarDay.yyyy-MM-dd`). The delete path's confirmation alert is bypassed in UI test mode because SwiftUI's nested alert button tree breaks XCUI automation — the alert is still shown to real users, and its functional correctness is covered by unit tests over `WorkoutEditor`.
