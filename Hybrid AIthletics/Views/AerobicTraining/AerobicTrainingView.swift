//
//  AerobicTrainingView.swift
//  Hybrid AIthletics
//
//  Top-level view for the Aerobic Training tab.
//  Shows a monthly calendar with exercise dots, a weekly calendar with
//  planned exercises, mileage stats, and sheets for adding/recording.
//

import SwiftUI
import SwiftData

/// The aerobic training tab displaying a monthly overview and weekly exercise plan.
struct AerobicTrainingView: View {
    @Environment(\.modelContext) private var modelContext
    @Environment(\.useMetricUnits) private var useMetricUnits
    @Environment(\.weekStartDay) private var weekStartDay
    @Query private var allExercises: [Exercise]

    /// The month displayed in the monthly calendar.
    @State private var selectedMonth: Date = Date()
    /// A date within the currently displayed week (normalized to the user's
    /// configured week start on navigation). Week boundaries always derive
    /// from `weekStart`/`weekEnd` since the environment isn't available here.
    @State private var selectedWeek: Date = Date().startOfDay
    /// The request passed to the schedule exercise sheet (nil = hidden).
    @State private var addExerciseRequest: AddExerciseRequest?
    /// The exercise selected for recording a workout.
    @State private var recordingExercise: Exercise?
    /// The exercise selected for editing its plan (uncompleted).
    @State private var editingExercise: Exercise?
    /// The completed exercise opened in the unified planned + completed editor.
    @State private var detailExercise: Exercise?
    /// Quick-add request (records a workout directly without scheduling first).
    @State private var quickAddRequest: QuickAddRequest?
    /// Navigation request from monthly calendar tap to highlight a day in the weekly view.
    @State private var exerciseNavigationRequest: ExerciseNavigationRequest?
    /// The edge new content slides in from during a weekly swipe transition.
    @State private var weekSlideEdge: Edge = .trailing

    /// Midnight on the first day of the displayed week per the user's week-start preference.
    private var weekStart: Date {
        selectedWeek.startOfWeek(firstWeekday: weekStartDay)
    }

    /// 23:59:59 on the last day of the displayed week per the user's week-start preference.
    private var weekEnd: Date {
        selectedWeek.endOfWeek(firstWeekday: weekStartDay)
    }

    /// Exercises scheduled within the currently displayed week.
    private var weekExercises: [Exercise] {
        let start = weekStart
        let end = weekEnd
        return allExercises.filter { $0.date >= start && $0.date <= end }
    }

    /// Calendar display items for the monthly overview.
    private var monthCalendarItems: [any CalendarDisplayable] {
        let start = selectedMonth.startOfMonth
        let end = selectedMonth.endOfMonth
        return allExercises.filter { $0.date >= start && $0.date <= end }
    }

    /// Sum of planned exercise distances for the current week, excluding
    /// exercises opted out of mileage totals.
    private var plannedMiles: Double {
        WeekMileage.planned(weekExercises)
    }

    /// Sum of recorded (actual) distances for the current week, excluding
    /// exercises opted out of mileage totals.
    private var completedMiles: Double {
        WeekMileage.completed(weekExercises)
    }

    /// Sum of planned exercise distances for the current week, including
    /// exercises opted out of mileage totals.
    private var allPlannedMiles: Double {
        WeekMileage.planned(weekExercises, includeNonTracked: true)
    }

    /// Sum of recorded (actual) distances for the current week, including
    /// exercises opted out of mileage totals.
    private var allCompletedMiles: Double {
        WeekMileage.completed(weekExercises, includeNonTracked: true)
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 0) {
                    MonthlyCalendarView(
                        selectedMonth: $selectedMonth,
                        items: monthCalendarItems,
                        onDayTap: handleMonthDayTap
                    )
                    .padding(.bottom, 8)
                    Divider()
                    weekHeader
                    Divider()
                    WeeklyCalendarView(
                        days: selectedWeek.daysInWeek(firstWeekday: weekStartDay),
                        exercises: weekExercises,
                        onAdd: { date in
                            addExerciseRequest = AddExerciseRequest(date: date)
                        },
                        onQuickAdd: { date in
                            quickAddRequest = QuickAddRequest(date: date)
                        },
                        onRecord: { exercise in
                            recordingExercise = exercise
                        },
                        onEdit: { exercise in
                            // Completed exercises open the unified planned +
                            // completed editor; planned-only ones open the
                            // plan editor.
                            if exercise.isCompleted {
                                detailExercise = exercise
                            } else {
                                editingExercise = exercise
                            }
                        },
                        navigationRequest: exerciseNavigationRequest
                    )
                    .id(selectedWeek)
                    .transition(.push(from: weekSlideEdge))
                }
            }
            .navigationTitle("Aerobic Training")
            .navigationBarTitleDisplayMode(.inline)
            .sheet(item: $addExerciseRequest) { request in
                AddExerciseSheet(exercise: nil, defaultDate: request.date)
                    .onDisappear {
                        // After scheduling, navigate to and highlight the day so the
                        // user sees their new exercise in the weekly view.
                        exerciseNavigationRequest = ExerciseNavigationRequest(targetDate: request.date)
                    }
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
            .sheet(item: $quickAddRequest) { request in
                RecordWorkoutSheet(exercise: nil, defaultDate: request.date)
            }
            .onChange(of: exerciseNavigationRequest) { _, newValue in
                guard let request = newValue else { return }
                Task { @MainActor in
                    try? await Task.sleep(for: .seconds(2.5))
                    if exerciseNavigationRequest?.id == request.id {
                        withAnimation(.easeInOut(duration: 0.4)) {
                            exerciseNavigationRequest = nil
                        }
                    }
                }
            }
        }
    }

    // MARK: - Month Calendar Navigation

    /// Navigates the weekly view to the week containing the tapped day.
    /// Days with existing items get highlighted; empty days open the schedule sheet.
    private func handleMonthDayTap(_ day: Date) {
        withAnimation {
            selectedWeek = day.startOfWeek(firstWeekday: weekStartDay)
        }
        if !day.isSameMonth(as: selectedMonth) {
            selectedMonth = day.startOfMonth
        }

        let hasItems = monthCalendarItems.contains {
            Calendar.current.isDate($0.displayDate, inSameDayAs: day)
        }
        if hasItems {
            exerciseNavigationRequest = ExerciseNavigationRequest(targetDate: day)
        } else {
            addExerciseRequest = AddExerciseRequest(date: day)
        }
    }

    /// Header showing week navigation and mileage stats.
    private var weekHeader: some View {
        VStack(spacing: 8) {
            // Week navigation
            HStack {
                Button { changeWeek(by: -1) } label: {
                    Image(systemName: "chevron.left")
                }
                Spacer()
                Text(weekLabel)
                    .font(.subheadline.bold())
                Spacer()
                Button { changeWeek(by: 1) } label: {
                    Image(systemName: "chevron.right")
                }
            }
            // Mileage stats
            HStack(spacing: 16) {
                MileageStat(
                    label: "Planned",
                    value: plannedMiles.formattedDistance(metric: useMetricUnits)
                )
                MileageStat(
                    label: "Completed",
                    value: completedMiles.formattedDistance(metric: useMetricUnits)
                )
                ProgressStat(
                    label: "Training Progress",
                    completedMiles: completedMiles,
                    plannedMiles: plannedMiles,
                    metric: useMetricUnits
                )
                ProgressStat(
                    label: "All Mileage",
                    completedMiles: allCompletedMiles,
                    plannedMiles: allPlannedMiles,
                    metric: useMetricUnits
                )
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 10)
        .background(.ultraThinMaterial)
        .contentShape(Rectangle())
        .gesture(
            DragGesture(minimumDistance: 30)
                .onEnded { value in
                    let horizontal = value.translation.width
                    let vertical = value.translation.height
                    guard abs(horizontal) > abs(vertical),
                          abs(horizontal) > 50 else { return }
                    if horizontal < 0 {
                        weekSlideEdge = .trailing
                        withAnimation(.easeInOut(duration: 0.25)) {
                            changeWeek(by: 1)
                        }
                    } else {
                        weekSlideEdge = .leading
                        withAnimation(.easeInOut(duration: 0.25)) {
                            changeWeek(by: -1)
                        }
                    }
                }
        )
    }

    /// Formatted label for the current week, e.g. "Apr 7 - Apr 13, 2026".
    private var weekLabel: String {
        let start = weekStart
        let end = Calendar.current.date(byAdding: .day, value: 6, to: start) ?? start
        let formatter = DateFormatter()
        formatter.dateFormat = "MMM d"
        let endFormatter = DateFormatter()
        endFormatter.dateFormat = "MMM d, yyyy"
        return "\(formatter.string(from: start)) - \(endFormatter.string(from: end))"
    }

    /// Navigates forward or backward by one week.
    private func changeWeek(by weeks: Int) {
        if let newWeek = Calendar.current.date(byAdding: .weekOfYear, value: weeks, to: weekStart) {
            selectedWeek = newWeek.startOfWeek(firstWeekday: weekStartDay)
        }
    }
}

// MARK: - Sheet Requests

/// Identifiable wrapper for the add-exercise sheet presentation.
private struct AddExerciseRequest: Identifiable {
    let id = UUID()
    let date: Date
}

/// Identifiable wrapper for the quick-add sheet presentation.
private struct QuickAddRequest: Identifiable {
    let id = UUID()
    let date: Date
}

/// A small stat display with a label and value.
private struct MileageStat: View {
    let label: String
    let value: String

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(value)
                .font(.caption.bold())
        }
    }
}

/// A completed-vs-planned fraction display colored by completion progress,
/// e.g. "3.0 / 10.0 mi".
private struct ProgressStat: View {
    let label: String
    let completedMiles: Double
    let plannedMiles: Double
    let metric: Bool

    var body: some View {
        VStack(spacing: 2) {
            Text(label)
                .font(.caption2)
                .foregroundStyle(.secondary)
            Text(text)
                .font(.caption.bold())
                .foregroundStyle(color)
        }
    }

    private var text: String {
        let completed = completedMiles.toDisplayDistance(metric: metric)
        let planned = plannedMiles.toDisplayDistance(metric: metric)
        let unit = metric ? "km" : "mi"
        return String(format: "%.1f / %.1f %@", completed, planned, unit)
    }

    private var color: Color {
        guard plannedMiles > 0 else { return .secondary }
        let fraction = completedMiles / plannedMiles
        if fraction >= 1.0 { return .green }
        if fraction >= 0.5 { return .orange }
        return .red
    }
}

#Preview {
    AerobicTrainingView()
        .modelContainer(ModelContainerFactory.makePreviewContainer())
}
