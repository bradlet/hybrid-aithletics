//
//  ReportFormatter.swift
//  CoachEvalKit
//
//  Plain-text rendering of run results and run comparisons. Pure functions
//  returning strings, so the formatting is testable and the CLI just prints.
//

import Foundation

/// Renders results for the terminal.
public enum ReportFormatter {

    /// One line per finished sample, e.g.
    /// `  ✔ sample 2/3  record_workout 2026-10-13 Tue · Easy Run · 5.0 mi  (31 tok/s)`.
    public static func sampleLine(_ result: SampleResult, sample: Int, of total: Int) -> String {
        let mark = result.passed ? "✔" : "✘"
        let what: String
        if let error = result.error {
            what = "error: \(error)"
        } else if let proposal = result.proposal {
            what = proposal
        } else {
            what = "reply: \(oneLine(result.reply, limit: 90))"
        }
        let speed = result.stats.map { String(format: "  (%.0f tok/s)", $0.tokensPerSecond) } ?? ""
        return "  \(mark) sample \(sample)/\(total)  \(what)\(speed)"
    }

    /// The failed checks of a sample, plus its full reply and rejections.
    public static func failureDetail(_ result: SampleResult) -> String {
        var lines: [String] = []
        for check in result.checks where !check.passed {
            lines.append("      ✘ \(check.label)" + (check.detail.isEmpty ? "" : " — \(check.detail)"))
        }
        for rejection in result.rejections {
            lines.append("      ! rejected tool call: \(rejection)")
        }
        if !result.reply.isEmpty {
            lines.append("      reply: \(oneLine(result.reply, limit: 400))")
        }
        return lines.joined(separator: "\n")
    }

    /// The end-of-run summary: one row per scenario with its pass rate and
    /// per-check rates, then the overall rate.
    public static func summary(_ record: RunRecord) -> String {
        var lines = [
            "",
            "Summary — \(record.modelID), \(record.samplesPerScenario) sample(s) per scenario, temperature \(record.config.temperature)",
            String(repeating: "─", count: 72),
        ]
        let idWidth = max(record.scenarios.map(\.id.count).max() ?? 0, 8)
        for scenario in record.scenarios {
            let rate = "\(scenario.passCount)/\(scenario.samples.count)"
            let speed = scenario.meanTokensPerSecond.map { String(format: "%5.0f tok/s", $0) } ?? ""
            lines.append("\(mark(scenario.passRate)) \(pad(scenario.id, idWidth))  \(pad(rate, 5))  \(speed)")
            for check in scenario.checkSummaries where check.passes < check.total {
                lines.append("    \(check.passes)/\(check.total)  \(check.label)")
            }
        }
        lines.append(String(repeating: "─", count: 72))
        lines.append(String(format: "Overall: %.0f%% of samples passed every check", record.passRate * 100))
        return lines.joined(separator: "\n")
    }

    /// A side-by-side comparison of two runs' per-scenario pass rates.
    public static func comparison(_ rows: [RunComparison.Row], before: RunRecord, after: RunRecord) -> String {
        let idWidth = max(rows.map(\.id.count).max() ?? 0, 8)
        var lines = [
            "before: \(describe(before))",
            "after:  \(describe(after))",
            "",
            "\(pad("scenario", idWidth))  before   after   change",
            String(repeating: "─", count: idWidth + 28),
        ]
        for row in rows {
            let delta: String
            if let change = row.change {
                delta = change == 0 ? "   =" : String(format: "%+4.0f%%", change * 100)
            } else {
                delta = "   n/a"
            }
            lines.append("\(pad(row.id, idWidth))  \(percent(row.before))  \(percent(row.after))  \(delta)")
        }
        lines.append(String(repeating: "─", count: idWidth + 28))
        lines.append("\(pad("overall", idWidth))  \(percent(before.passRate))  \(percent(after.passRate))")
        return lines.joined(separator: "\n")
    }

    // MARK: - Helpers

    /// `✔` for a full pass, `~` for a partial pass, `✘` for none.
    static func mark(_ rate: Double) -> String {
        rate >= 1 ? "✔" : (rate > 0 ? "~" : "✘")
    }

    /// Collapses whitespace and truncates with an ellipsis.
    static func oneLine(_ text: String, limit: Int) -> String {
        let flat = text.split(whereSeparator: \.isNewline).joined(separator: " ")
        return flat.count > limit ? String(flat.prefix(limit)) + "…" : flat
    }

    /// Right-pads to `width` characters.
    static func pad(_ text: String, _ width: Int) -> String {
        text.count >= width ? text : text + String(repeating: " ", count: width - text.count)
    }

    /// `" 67%"`-style fixed-width percentage, or `"   - "` when absent.
    static func percent(_ rate: Double?) -> String {
        guard let rate else { return "    - " }
        return String(format: "%5.0f%%", rate * 100)
    }

    /// One-line identity of a run: when, which commit, any note.
    static func describe(_ record: RunRecord) -> String {
        let commit = record.gitCommit.map { " @ \($0)" } ?? ""
        let note = record.note.map { " — \($0)" } ?? ""
        return "\(record.startedAt.formatted(date: .abbreviated, time: .shortened))\(commit)\(note)"
    }
}

/// Lines up two runs scenario by scenario.
public enum RunComparison {

    /// One scenario's pass rate in each run. A scenario present in only one
    /// run has `nil` on the other side.
    public struct Row: Equatable, Sendable {
        /// Scenario id.
        public let id: String
        /// Pass rate in the earlier run.
        public let before: Double?
        /// Pass rate in the later run.
        public let after: Double?

        /// `after - before`, when both exist.
        public var change: Double? {
            guard let before, let after else { return nil }
            return after - before
        }
    }

    /// Pairs scenarios by id: the earlier run's order first, then any
    /// scenarios only the later run has.
    public static func rows(before: RunRecord, after: RunRecord) -> [Row] {
        let afterRates = Dictionary(after.scenarios.map { ($0.id, $0.passRate) }, uniquingKeysWith: { a, _ in a })
        let beforeIDs = Set(before.scenarios.map(\.id))
        let shared = before.scenarios.map { Row(id: $0.id, before: $0.passRate, after: afterRates[$0.id]) }
        let added = after.scenarios
            .filter { !beforeIDs.contains($0.id) }
            .map { Row(id: $0.id, before: nil, after: $0.passRate) }
        return shared + added
    }
}
