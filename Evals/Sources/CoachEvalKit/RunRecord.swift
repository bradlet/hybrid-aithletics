//
//  RunRecord.swift
//  CoachEvalKit
//
//  The results of one eval run, Codable so `run --save` can write them to
//  `results/` and `compare` can diff two runs later.
//

import Foundation
import AICoachCore

/// One check's outcome on one sample.
public struct CheckResult: Codable, Equatable, Sendable {
    /// The expectation's label.
    public var label: String
    /// Whether it passed.
    public var passed: Bool
    /// What was observed.
    public var detail: String

    /// Creates a check result.
    public init(label: String, passed: Bool, detail: String) {
        self.label = label
        self.passed = passed
        self.detail = detail
    }
}

/// One generated turn and how it scored.
public struct SampleResult: Codable, Equatable, Sendable {
    /// Every check, in the scenario's order.
    public var checks: [CheckResult]
    /// The reply text the athlete would read.
    public var reply: String
    /// The proposal card, rendered with `ProposalSummary`, if any.
    public var proposal: String?
    /// Rejected tool calls.
    public var rejections: [String]
    /// Set when generation itself threw; every check then fails.
    public var error: String?
    /// Token counts and timings.
    public var stats: TurnStats?

    /// Creates a sample result.
    public init(
        checks: [CheckResult],
        reply: String,
        proposal: String?,
        rejections: [String],
        error: String? = nil,
        stats: TurnStats? = nil
    ) {
        self.checks = checks
        self.reply = reply
        self.proposal = proposal
        self.rejections = rejections
        self.error = error
        self.stats = stats
    }

    /// A sample passes only when every check passes and nothing threw.
    public var passed: Bool {
        error == nil && checks.allSatisfy(\.passed)
    }
}

/// One check's pass rate across a scenario's samples.
public struct CheckSummary: Equatable, Sendable {
    /// The expectation's label.
    public let label: String
    /// Samples where it passed.
    public let passes: Int
    /// Samples run.
    public let total: Int
}

/// Every sample of one scenario.
public struct ScenarioResult: Codable, Equatable, Sendable {
    /// The scenario's id.
    public var id: String
    /// The scenario's title.
    public var title: String
    /// The scenario's tags, sorted.
    public var tags: [String]
    /// One entry per sample.
    public var samples: [SampleResult]

    /// Creates a scenario result.
    public init(id: String, title: String, tags: [String], samples: [SampleResult]) {
        self.id = id
        self.title = title
        self.tags = tags
        self.samples = samples
    }

    /// Samples where every check passed.
    public var passCount: Int { samples.filter(\.passed).count }

    /// Fraction of samples that fully passed, `0...1`.
    public var passRate: Double {
        samples.isEmpty ? 0 : Double(passCount) / Double(samples.count)
    }

    /// Per-check pass counts, in the scenario's check order.
    ///
    /// Shows *which* part of a scenario is flaky — "the date is always right
    /// but the distance is wrong half the time" — which a single pass rate hides.
    public var checkSummaries: [CheckSummary] {
        guard let first = samples.first(where: { $0.error == nil }) else { return [] }
        return first.checks.indices.map { index in
            let passes = samples.filter { sample in
                sample.checks.indices.contains(index) && sample.checks[index].passed
            }.count
            return CheckSummary(label: first.checks[index].label, passes: passes, total: samples.count)
        }
    }

    /// Mean generation speed across samples that reported stats.
    public var meanTokensPerSecond: Double? {
        let rates = samples.compactMap { $0.stats?.tokensPerSecond }
        return rates.isEmpty ? nil : rates.reduce(0, +) / Double(rates.count)
    }
}

/// A whole eval run.
public struct RunRecord: Codable, Sendable {
    /// When the run started.
    public var startedAt: Date
    /// The git commit the run was made from, when known.
    public var gitCommit: String?
    /// Free-form note, e.g. what prompt change this run tests.
    public var note: String?
    /// The model that generated.
    public var modelID: String
    /// Sampling parameters used.
    public var config: GenerationConfig
    /// Samples generated per scenario.
    public var samplesPerScenario: Int
    /// Per-scenario results, in run order.
    public var scenarios: [ScenarioResult]

    /// Creates a run record.
    public init(
        startedAt: Date,
        gitCommit: String? = nil,
        note: String? = nil,
        modelID: String,
        config: GenerationConfig,
        samplesPerScenario: Int,
        scenarios: [ScenarioResult]
    ) {
        self.startedAt = startedAt
        self.gitCommit = gitCommit
        self.note = note
        self.modelID = modelID
        self.config = config
        self.samplesPerScenario = samplesPerScenario
        self.scenarios = scenarios
    }

    /// Fraction of all samples, across all scenarios, that fully passed.
    public var passRate: Double {
        let all = scenarios.flatMap(\.samples)
        return all.isEmpty ? 0 : Double(all.filter(\.passed).count) / Double(all.count)
    }

    /// Encodes as pretty, key-sorted JSON (stable diffs if you commit one).
    public func jsonData() throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(self)
    }

    /// Decodes a record written by `jsonData()`.
    public static func decode(_ data: Data) throws -> RunRecord {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(RunRecord.self, from: data)
    }
}
