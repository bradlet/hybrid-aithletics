//
//  PromptBuilderTests.swift
//  AICoachCoreTests
//
//  Unit tests for AICoachPromptBuilder, migrated from the app's test suite
//  and adapted to use AICoachCore's plain types (CoachWorkout, CoachExercise).
//

import Testing
import Foundation
@testable import AICoachCore

// MARK: - AI Coach Prompt Builder Tests

struct AICoachPromptBuilderTests {

    /// Helper to build a workout at a specific date for deterministic prompt output.
    private func makeWorkout(
        date: Date,
        type: CoachExerciseType = .easyRun,
        distanceMiles: Double = 4.0,
        durationSeconds: Int = 2100,
        feeling: Int? = nil,
        perceivedExertion: Int? = nil,
        notes: String = ""
    ) -> CoachWorkout {
        CoachWorkout(
            date: date,
            type: type,
            distanceMiles: distanceMiles,
            durationSeconds: durationSeconds,
            feeling: feeling,
            perceivedExertion: perceivedExertion,
            notes: notes
        )
    }

    private func makeExercise(
        date: Date,
        type: CoachExerciseType = .run,
        distanceMiles: Double = 5.0,
        durationSeconds: Int = 2400
    ) -> CoachExercise {
        CoachExercise(
            scheduledDate: date,
            type: type,
            distanceMiles: distanceMiles,
            durationSeconds: durationSeconds
        )
    }

    @Test func promptIncludesEveryRecentWorkout() {
        let w1 = makeWorkout(date: Date(timeIntervalSince1970: 1_800_000_000), perceivedExertion: 3)
        let w2 = makeWorkout(date: Date(timeIntervalSince1970: 1_800_100_000), perceivedExertion: 7)
        let request = CoachingRequest(
            recentWorkouts: [w1, w2],
            upcomingExercises: [],
            useMetricUnits: false
        )
        let prompt = AICoachPromptBuilder.buildPrompt(for: request)
        #expect(prompt.contains("RPE 3/10"))
        #expect(prompt.contains("RPE 7/10"))
        #expect(prompt.contains("Recent training (2 workouts)"))
    }

    @Test func promptOmitsRPEOnWorkoutLineWhenUnrated() {
        let unrated = makeWorkout(date: Date(), perceivedExertion: nil)
        let rated = makeWorkout(date: Date(), perceivedExertion: 6)
        let unratedLine = AICoachPromptBuilder.workoutLine(unrated, metric: false)
        let ratedLine = AICoachPromptBuilder.workoutLine(rated, metric: false)
        #expect(!unratedLine.contains("RPE"))
        #expect(ratedLine.contains("RPE 6/10"))
    }

    @Test func workoutLineOmitsFeelingWhenNil() {
        let workout = makeWorkout(date: Date(), feeling: nil, perceivedExertion: 6)
        let line = AICoachPromptBuilder.workoutLine(workout, metric: false)
        #expect(!line.contains("felt"))
    }

    @Test func workoutLineIncludesFeelingWhenSet() {
        let workout = makeWorkout(date: Date(), feeling: 2)
        let line = AICoachPromptBuilder.workoutLine(workout, metric: false)
        #expect(line.contains("felt weak"))
    }

    @Test func workoutLineOmitsBothRatingsWhenUnrated() {
        let workout = makeWorkout(date: Date())
        let line = AICoachPromptBuilder.workoutLine(workout, metric: false)
        #expect(!line.contains("RPE"))
        #expect(!line.contains("felt"))
    }

    @Test func workoutLineEmitsExertionBeforeFeeling() {
        let date = ISO8601DateFormatter().date(from: "2026-07-28T12:00:00Z")!
        let workout = makeWorkout(
            date: date,
            type: .run,
            distanceMiles: 6.0,
            durationSeconds: 3130,
            feeling: 2,
            perceivedExertion: 8
        )
        let line = AICoachPromptBuilder.workoutLine(workout, metric: false)
        #expect(line == "- 2026-07-28 Tue Run, 6.0 mi, 52:10, RPE 8/10, felt weak")
    }

    /// Regression guard on the deleted felt-rating → RPE inversion, which used
    /// to turn an 8 into `RPE 2/10` (and a 10 into an off-scale `RPE 0/10`).
    @Test func workoutLineNoLongerInvertsExertion() {
        let line = AICoachPromptBuilder.workoutLine(
            makeWorkout(date: Date(), perceivedExertion: 8), metric: false
        )
        #expect(line.contains("RPE 8/10"))
        #expect(!line.contains("RPE 2/10"))
    }

    @Test func maximumExertionStaysOnScale() {
        let line = AICoachPromptBuilder.workoutLine(
            makeWorkout(date: Date(), perceivedExertion: 10), metric: false
        )
        #expect(line.contains("RPE 10/10"))
    }

    @Test func feelingDescriptorCoversEveryLevel() {
        #expect(AICoachPromptBuilder.feelingDescriptor(1) == "very weak")
        #expect(AICoachPromptBuilder.feelingDescriptor(2) == "weak")
        #expect(AICoachPromptBuilder.feelingDescriptor(3) == "normal")
        #expect(AICoachPromptBuilder.feelingDescriptor(4) == "strong")
        #expect(AICoachPromptBuilder.feelingDescriptor(5) == "very strong")
    }

    @Test func feelingDescriptorClampsOutOfRange() {
        #expect(AICoachPromptBuilder.feelingDescriptor(0) == "very weak")
        #expect(AICoachPromptBuilder.feelingDescriptor(-4) == "very weak")
        #expect(AICoachPromptBuilder.feelingDescriptor(9) == "very strong")
    }

    @Test func systemPreambleMentionsBothSignals() {
        #expect(AICoachPromptBuilder.systemPreamble.contains("RPE, 1–10"))
        #expect(AICoachPromptBuilder.systemPreamble.contains("very weak → very strong"))
    }

    @Test func promptIncludesNotesWhenPresent() {
        let workout = makeWorkout(date: Date(), notes: "legs felt heavy")
        let line = AICoachPromptBuilder.workoutLine(workout, metric: false)
        #expect(line.contains("\"legs felt heavy\""))
    }

    @Test func promptOmitsNotesWhenBlank() {
        let workout = makeWorkout(date: Date(), notes: "   ")
        let line = AICoachPromptBuilder.workoutLine(workout, metric: false)
        #expect(!line.contains("\""))
    }

    @Test func promptRespectsMetricUnits() {
        let workout = makeWorkout(date: Date(), distanceMiles: 5.0)
        let imperial = AICoachPromptBuilder.workoutLine(workout, metric: false)
        let metric = AICoachPromptBuilder.workoutLine(workout, metric: true)
        #expect(imperial.contains("mi"))
        #expect(metric.contains("km"))
    }

    @Test func promptIncludesUpcomingExercisesInOrder() {
        let earlier = makeExercise(date: Date(timeIntervalSince1970: 1_800_000_000))
        let later = makeExercise(date: Date(timeIntervalSince1970: 1_800_200_000))
        let request = CoachingRequest(
            recentWorkouts: [],
            upcomingExercises: [earlier, later],
            useMetricUnits: false
        )
        let prompt = AICoachPromptBuilder.buildPrompt(for: request)
        #expect(prompt.contains("Upcoming plan (2 scheduled)"))
        let earlierString = prompt.range(of: AICoachPromptBuilder.exerciseLine(earlier, metric: false))
        let laterString = prompt.range(of: AICoachPromptBuilder.exerciseLine(later, metric: false))
        #expect(earlierString != nil)
        #expect(laterString != nil)
        if let a = earlierString, let b = laterString {
            #expect(a.lowerBound < b.lowerBound)
        }
    }

    @Test func promptHandlesEmptyInputs() {
        let request = CoachingRequest(
            recentWorkouts: [],
            upcomingExercises: [],
            useMetricUnits: false
        )
        let prompt = AICoachPromptBuilder.buildPrompt(for: request)
        #expect(prompt.contains("(no workouts recorded"))
        #expect(prompt.contains("(no upcoming exercises"))
    }

    @Test func promptContainsSystemPreamble() {
        let request = CoachingRequest(
            recentWorkouts: [],
            upcomingExercises: [],
            useMetricUnits: false
        )
        let prompt = AICoachPromptBuilder.buildPrompt(for: request)
        #expect(prompt.contains("experienced competitive running coach"))
    }

    @Test func workoutLineIncludesDateAndType() {
        let date = ISO8601DateFormatter().date(from: "2026-04-06T12:00:00Z")!
        let workout = makeWorkout(date: date, type: .tempoRun)
        let line = AICoachPromptBuilder.workoutLine(workout, metric: false)
        #expect(line.hasPrefix("- 2026-04-06"))
        #expect(line.contains(CoachExerciseType.tempoRun.rawValue))
    }

    @Test func exerciseLineIncludesDateAndType() {
        let date = ISO8601DateFormatter().date(from: "2026-04-07T12:00:00Z")!
        let exercise = makeExercise(date: date, type: .longRun, distanceMiles: 10.0)
        let line = AICoachPromptBuilder.exerciseLine(exercise, metric: false)
        #expect(line.hasPrefix("- "))
        #expect(line.contains(CoachExerciseType.longRun.rawValue))
        #expect(line.contains("mi"))
    }

    @Test func exerciseLineRespectsMetricUnits() {
        let exercise = makeExercise(date: Date(), distanceMiles: 5.0)
        let imperial = AICoachPromptBuilder.exerciseLine(exercise, metric: false)
        let metric = AICoachPromptBuilder.exerciseLine(exercise, metric: true)
        #expect(imperial.contains("mi"))
        #expect(metric.contains("km"))
    }

    @Test func promptIncludesBulletPointFormatInstruction() {
        let request = CoachingRequest(
            recentWorkouts: [],
            upcomingExercises: [],
            useMetricUnits: false
        )
        let prompt = AICoachPromptBuilder.buildPrompt(for: request)
        #expect(prompt.contains("3–5 bullet points"))
        #expect(prompt.contains("Do not repeat yourself"))
    }

    @Test func promptEndsWithCoachingQuestion() {
        let request = CoachingRequest(
            recentWorkouts: [],
            upcomingExercises: [],
            useMetricUnits: false
        )
        let prompt = AICoachPromptBuilder.buildPrompt(for: request)
        #expect(prompt.contains("what should change about the upcoming plan"))
    }

    // MARK: - buildUserContent tests

    @Test func userContentExcludesSystemPreamble() {
        let request = CoachingRequest(
            recentWorkouts: [],
            upcomingExercises: [],
            useMetricUnits: false
        )
        let content = AICoachPromptBuilder.buildUserContent(for: request)
        #expect(!content.contains("experienced competitive running coach"))
        #expect(content.contains("Recent training"))
        #expect(content.contains("what should change about the upcoming plan"))
    }

    @Test func buildPromptEqualsPreamblePlusUserContent() {
        let w = makeWorkout(date: Date(), feeling: 3, perceivedExertion: 5)
        let e = makeExercise(date: Date())
        let request = CoachingRequest(
            recentWorkouts: [w],
            upcomingExercises: [e],
            useMetricUnits: false
        )
        let full = AICoachPromptBuilder.buildPrompt(for: request)
        let expected = AICoachPromptBuilder.systemPreamble + "\n\n"
            + AICoachPromptBuilder.buildUserContent(for: request)
        #expect(full == expected)
    }

    @Test func userContentIncludesWorkoutData() {
        let w = makeWorkout(date: Date(), feeling: 4, perceivedExertion: 8, notes: "felt great")
        let request = CoachingRequest(
            recentWorkouts: [w],
            upcomingExercises: [],
            useMetricUnits: false
        )
        let content = AICoachPromptBuilder.buildUserContent(for: request)
        #expect(content.contains("RPE 8/10"))
        #expect(content.contains("felt strong"))
        #expect(content.contains("\"felt great\""))
    }

    // MARK: - buildDataSections

    @Test func dataSectionsIsPrefixOfUserContent() {
        let request = CoachingRequest(
            recentWorkouts: [
                makeWorkout(date: Date(timeIntervalSince1970: 1_800_000_000), perceivedExertion: 6),
                makeWorkout(date: Date(timeIntervalSince1970: 1_800_100_000), feeling: 2),
            ],
            upcomingExercises: [makeExercise(date: Date(timeIntervalSince1970: 1_800_200_000))],
            useMetricUnits: false
        )
        let sections = AICoachPromptBuilder.buildDataSections(for: request)
        let content = AICoachPromptBuilder.buildUserContent(for: request)
        #expect(content.hasPrefix(sections))
        #expect(content == sections + "\n" + AICoachPromptBuilder.closingQuestion)
    }

    @Test func dataSectionsOmitsClosingQuestion() {
        let request = CoachingRequest(
            recentWorkouts: [],
            upcomingExercises: [],
            useMetricUnits: false
        )
        let sections = AICoachPromptBuilder.buildDataSections(for: request)
        #expect(!sections.contains(AICoachPromptBuilder.closingQuestion))
        #expect(sections.contains("no workouts recorded"))
        #expect(sections.contains("no upcoming exercises"))
    }

    @Test func dataSectionsRendersMetricAndImperial() {
        let request = CoachingRequest(
            recentWorkouts: [makeWorkout(date: Date(), distanceMiles: 5.0)],
            upcomingExercises: [],
            useMetricUnits: false
        )
        let metricRequest = CoachingRequest(
            recentWorkouts: request.recentWorkouts,
            upcomingExercises: [],
            useMetricUnits: true
        )
        #expect(AICoachPromptBuilder.buildDataSections(for: request).contains("mi"))
        #expect(AICoachPromptBuilder.buildDataSections(for: metricRequest).contains("km"))
    }
}

// MARK: - Distance Formatting Tests

struct DistanceFormattingTests {

    @Test func imperialFormatting() {
        let result = 5.0.formattedDistance(metric: false)
        #expect(result == "5.0 mi")
    }

    @Test func metricFormatting() {
        let result = 5.0.formattedDistance(metric: true)
        #expect(result.contains("km"))
        #expect(result.hasPrefix("8.0"))  // 5.0 * 1.60934 ≈ 8.0
    }

    @Test func toDisplayDistanceMiles() {
        #expect(5.0.toDisplayDistance(metric: false) == 5.0)
    }

    @Test func toDisplayDistanceKilometers() {
        let km = 5.0.toDisplayDistance(metric: true)
        #expect(km > 8.0 && km < 8.1)
    }
}

// MARK: - Duration Formatting Tests

struct DurationFormattingTests {

    @Test func minutesAndSeconds() {
        #expect(2100.formattedDuration == "35:00")
    }

    @Test func hoursMinutesSeconds() {
        #expect(3661.formattedDuration == "1:01:01")
    }

    @Test func doubleFormattedDuration() {
        #expect(Double(2700).formattedDuration == "45:00")
    }
}

// MARK: - Generation Config Tests

struct GenerationConfigTests {

    @Test func productionDefaults() {
        let config = GenerationConfig.production
        #expect(config.maxTokens == 400)
        #expect(config.temperature == 0.4)
        #expect(config.topP == 0.9)
        #expect(config.repetitionPenalty == 1.2)
        #expect(config.repetitionContextSize == 200)
    }

    @Test func chatPresetGivesMoreHeadroomThanProduction() {
        let config = GenerationConfig.chat
        #expect(config.maxTokens == 512)
        #expect(config.temperature == 0.6)
        #expect(config.topP == 0.95)
        // The looping failure mode on this model is real; the penalty holds.
        #expect(config.repetitionPenalty == GenerationConfig.production.repetitionPenalty)
        #expect(config.maxTokens > GenerationConfig.production.maxTokens)
    }

    @Test func codableRoundTrip() throws {
        let original = GenerationConfig(maxTokens: 300, temperature: 0.3)
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(GenerationConfig.self, from: data)
        #expect(decoded.maxTokens == original.maxTokens)
        #expect(decoded.temperature == original.temperature)
    }
}

// MARK: - Coach Exercise Type Tests

struct CoachExerciseTypeTests {

    @Test func allCasesHaveRawValues() {
        for type in CoachExerciseType.allCases {
            #expect(!type.rawValue.isEmpty)
        }
    }

    @Test func codableRoundTrip() throws {
        let original = CoachExerciseType.tempoRun
        let data = try JSONEncoder().encode(original)
        let decoded = try JSONDecoder().decode(CoachExerciseType.self, from: data)
        #expect(decoded == original)
    }

    @Test func rawValuesMatchAppExerciseType() {
        // Verify a representative sample of raw values match the app's ExerciseType.
        #expect(CoachExerciseType.run.rawValue == "Run")
        #expect(CoachExerciseType.longRun.rawValue == "Long Run")
        #expect(CoachExerciseType.tempoRun.rawValue == "Tempo Run")
        #expect(CoachExerciseType.intervalRun.rawValue == "Interval Run")
        #expect(CoachExerciseType.easyRun.rawValue == "Easy Run")
        #expect(CoachExerciseType.recoveryRun.rawValue == "Recovery Run")
    }
}
