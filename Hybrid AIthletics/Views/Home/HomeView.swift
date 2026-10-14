//
//  HomeView.swift
//  Hybrid AIthletics
//
//  The app's landing tab: today's training, a quick way to record it, and the
//  entry point into the coach conversation.
//
//  This is the query-owning top-level view per the project's no-ViewModels
//  convention — child views receive data as `let` parameters.
//

import SwiftUI
import SwiftData
import AICoachCore

/// The Home tab.
struct HomeView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.useMetricUnits) private var useMetricUnits
    @Environment(\.coachChat) private var coachChat

    @Query private var allExercises: [Exercise]
    @Query private var allStrengthExercises: [StrengthExercise]

    /// Quick-add request (records a workout with no planned exercise behind it).
    @State private var quickAddRequest: QuickAddWorkoutRequest?
    /// The exercise being recorded against.
    @State private var recordingExercise: Exercise?
    /// A planned-only exercise opened for plan editing.
    @State private var editingExercise: Exercise?
    /// A recorded exercise opened in the unified planned + completed editor.
    @State private var detailExercise: Exercise?
    /// The strength exercise a weight is being recorded against.
    @State private var recordingStrength: StrengthExercise?
    /// Whether the lift picker for today's lane is showing.
    @State private var isLiftPickerPresented = false
    /// Whether the exercise library is showing (used when today's lane is empty).
    @State private var isLibraryPresented = false
    /// A coach workout proposal the athlete accepted, pending confirmation in
    /// the record sheet.
    @State private var proposedWorkout: ProposedWorkoutRequest?
    /// Error surfaced when an accepted schedule change could not be applied.
    @State private var applyErrorMessage: String?

    /// Today's aerobic sessions, unrecorded first.
    private var todayAerobic: [Exercise] {
        TodayTraining.aerobic(allExercises, on: Date())
    }

    /// Today's active strength lane.
    private var todayStrength: [StrengthExercise] {
        TodayTraining.strength(allStrengthExercises, on: Date())
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 20) {
                    NavigationLink {
                        CoachChatView(
                            buildContext: buildCoachRequest,
                            onAcceptWorkout: { proposal, messageID in
                                proposedWorkout = ProposedWorkoutRequest(
                                    prefill: CoachProposalApplier.prefill(from: proposal),
                                    messageID: messageID
                                )
                            },
                            onAcceptScheduleChange: applyScheduleChange
                        )
                    } label: {
                        CoachEntryCard(
                            lastReply: coachChat.lastCoachReply,
                            isGenerating: coachChat.isGenerating
                        )
                    }
                    .buttonStyle(.plain)
                    .accessibilityIdentifier("home.coachCard")

                    TodayTrainingSection(
                        aerobic: todayAerobic,
                        strength: todayStrength,
                        onRecordAerobic: { recordingExercise = $0 },
                        onEditAerobic: { exercise in
                            // Matches the Training tab: a recorded exercise opens
                            // the unified editor, a planned-only one the planner.
                            if exercise.isCompleted {
                                detailExercise = exercise
                            } else {
                                editingExercise = exercise
                            }
                        },
                        onRecordStrength: { recordingStrength = $0 }
                    )

                    QuickRecordSection(
                        onLogWorkout: {
                            quickAddRequest = QuickAddWorkoutRequest(date: Date())
                        },
                        onLogLift: {
                            if todayStrength.isEmpty {
                                isLibraryPresented = true
                            } else if todayStrength.count == 1 {
                                recordingStrength = todayStrength[0]
                            } else {
                                isLiftPickerPresented = true
                            }
                        }
                    )
                }
                .padding()
            }
            .background(Color(.systemGroupedBackground))
            .navigationTitle("Home")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $quickAddRequest) { request in
                RecordWorkoutSheet(exercise: nil, defaultDate: request.date)
            }
            .sheet(item: $recordingExercise) { exercise in
                RecordWorkoutSheet(exercise: exercise, defaultDate: exercise.date)
            }
            .sheet(item: $editingExercise) { exercise in
                AddExerciseSheet(exercise: exercise, defaultDate: exercise.date)
            }
            .sheet(item: $detailExercise) { exercise in
                WorkoutDetailSheet(exercise: exercise)
            }
            .sheet(item: $recordingStrength) { exercise in
                RecordStrengthWorkoutSheet(exercise: exercise)
            }
            .sheet(item: $proposedWorkout) { request in
                RecordWorkoutSheet(
                    exercise: nil,
                    defaultDate: request.prefill.date,
                    prefill: request.prefill
                )
            }
            .sheet(isPresented: $isLibraryPresented) {
                ExerciseLibrarySheet(
                    provider: .withUserLibrary(container: modelContext.container)
                ) { entry, plan in
                    addLiftFromLibrary(entry, plan: plan)
                }
            }
            .confirmationDialog(
                "Which lift?",
                isPresented: $isLiftPickerPresented,
                titleVisibility: .visible
            ) {
                ForEach(todayStrength) { exercise in
                    Button(exercise.name) { recordingStrength = exercise }
                }
                Button("Cancel", role: .cancel) { }
            }
            .alert(
                "Couldn't apply that",
                isPresented: Binding(
                    get: { applyErrorMessage != nil },
                    set: { if !$0 { applyErrorMessage = nil } }
                ),
                presenting: applyErrorMessage
            ) { _ in
                Button("OK", role: .cancel) { applyErrorMessage = nil }
            } message: { message in
                Text(message)
            }
        }
    }

    // MARK: - Coach

    /// Assembles the training snapshot handed to the coach: the last 4 weeks of
    /// recorded workouts and the next 2 weeks of planned sessions.
    ///
    /// Moved here from `AerobicTrainingView` along with the coach entry point.
    /// The query-owning top-level view is the right place to read SwiftData per
    /// the project's no-ViewModels convention.
    private func buildCoachRequest() -> CoachingRequest {
        let now = Date()
        let calendar = Calendar.current
        let fourWeeksAgo = calendar.date(byAdding: .weekOfYear, value: -4, to: now) ?? now
        let twoWeeksAhead = calendar.date(byAdding: .weekOfYear, value: 2, to: now) ?? now

        let recent = allExercises
            .filter { $0.isCompleted && $0.date >= fourWeeksAgo && $0.date <= now }
            .sorted { $0.date < $1.date }
            .map { CoachWorkout(from: $0) }

        let upcoming = allExercises
            .filter { !$0.isCompleted && $0.date >= now.startOfDay && $0.date <= twoWeeksAhead }
            .sorted { $0.date < $1.date }
            .map { CoachExercise(from: $0) }

        return CoachingRequest(
            recentWorkouts: recent,
            upcomingExercises: upcoming,
            useMetricUnits: useMetricUnits
        )
    }

    /// Applies an accepted schedule change, reporting a failure to the athlete
    /// rather than silently doing nothing.
    private func applyScheduleChange(
        _ proposal: ScheduleChangeProposal,
        messageID: UUID
    ) {
        do {
            try CoachProposalApplier.apply(proposal, in: modelContext)
            coachChat.confirmProposal(for: messageID, note: "Done — I've updated your plan.")
        } catch {
            applyErrorMessage = error.localizedDescription
        }
    }

    // MARK: - Strength

    /// Adds a library entry to today's lane and immediately opens recording,
    /// which is what "Log Lift" with an empty lane is asking for.
    private func addLiftFromLibrary(_ entry: LibraryExercise, plan: StrengthPlanDraft) {
        let today = Date().weekdayIndex
        let exercise = StrengthExercise(
            name: entry.name,
            libraryExerciseID: entry.id,
            muscleGroup: entry.muscleGroup,
            weekdayIndex: today,
            sortOrder: StrengthBoardPlanner.nextSortOrder(
                allStrengthExercises, day: today, offloaded: false
            ),
            plannedSets: plan.plannedSets,
            plannedReps: plan.plannedReps
        )
        modelContext.insert(exercise)
        recordingStrength = exercise
    }
}

// MARK: - Sheet Requests

/// Identifiable wrapper for the quick-add workout sheet.
private struct QuickAddWorkoutRequest: Identifiable {
    let id = UUID()
    let date: Date
}

/// Identifiable wrapper for a coach-proposed workout awaiting confirmation.
private struct ProposedWorkoutRequest: Identifiable {
    let id = UUID()
    let prefill: CoachProposalApplier.WorkoutPrefill
    /// The coach turn the proposal came from, so it can be resolved on save.
    let messageID: UUID
}

#Preview {
    HomeView()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
