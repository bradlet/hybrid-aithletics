//
//  EvalCalendar.swift
//  CoachEvalKit
//
//  The fixed "today" every scenario runs against, and the day arithmetic the
//  scenarios and expectations share.
//

import Foundation

/// Date helpers anchored to a fixed, reproducible "today".
///
/// The model has no clock: the runtime tells it what day it is. Pinning that
/// day makes a scenario's relative dates ("yesterday", "Tuesday") resolve the
/// same way on every run, so a score change means the *model* changed its
/// answer, not the calendar.
public enum EvalCalendar {

    /// Wednesday 2026-10-14 at noon, local time.
    ///
    /// A Wednesday so "Monday" and "Friday" are unambiguous in either
    /// direction, and noon so no DST transition can push a day offset across
    /// midnight.
    public static let today: Date = {
        var components = DateComponents()
        components.year = 2026
        components.month = 10
        components.day = 14
        components.hour = 12
        return Calendar.current.date(from: components)!
    }()

    /// The date `offset` days from `today` (negative is the past).
    /// - Parameters:
    ///   - offset: Days to add; `-1` is yesterday.
    ///   - today: The anchor. Defaults to the fixed eval date.
    /// - Returns: The shifted date, keeping the anchor's time of day.
    public static func day(_ offset: Int, from today: Date = today) -> Date {
        Calendar.current.date(byAdding: .day, value: offset, to: today)!
    }

    /// Whether two dates fall on the same local calendar day.
    public static func isSameDay(_ a: Date, _ b: Date) -> Bool {
        Calendar.current.isDate(a, inSameDayAs: b)
    }

    /// Formats a date as `yyyy-MM-dd EEE`, e.g. `2026-10-13 Tue`, for reports.
    public static func label(_ date: Date) -> String {
        labelFormatter.string(from: date)
    }

    /// Cached formatter for `label(_:)`; never allocate one per call.
    private static let labelFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd EEE"
        return formatter
    }()
}
