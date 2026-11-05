//
//  CSVImportHelpView.swift
//  Hybrid AIthletics
//
//  Help page explaining the expected CSV format for workout imports.
//  Exercise type values are generated dynamically from ExerciseType.allCases
//  so the list stays in sync as new types are added.
//

import SwiftUI

/// Explains the CSV import format, column order, and accepted values.
struct CSVImportHelpView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                columnOrderSection
                dateSection
                nameSection
                typeSection
                durationSection
                distanceSection
                optionalFieldsSection
                exampleSection
            }
            .navigationTitle("CSV Format")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                }
            }
        }
    }

    // MARK: - Sections

    private var columnOrderSection: some View {
        Section {
            Text("date, name, type, duration, distance, notes, feeling, perceived_exertion")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.primary)
            Text("The first row of your CSV must be a header. Column order is fixed and must match the order above.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Column Order")
        }
    }

    private var dateSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                helpRow("M/D/YYYY", detail: "8/4/2025")
                helpRow("YYYY-MM-DD", detail: "2025-08-04")
                helpRow("ISO 8601", detail: "2025-08-04T07:30:00Z")
            }
        } header: {
            Text("Date Formats")
        } footer: {
            Text("All three formats are accepted. Single-digit months and days are fine (e.g., 8/4/2025).")
        }
    }

    private var nameSection: some View {
        Section {
            Text("The workout name is optional. If left blank, it will be set to the exercise type's display name (e.g., type \"easy\" with no name becomes \"Easy Run\").")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Name (Optional)")
        }
    }

    private var typeSection: some View {
        Section {
            ForEach(ExerciseType.allCases) { type in
                HStack {
                    Image(systemName: type.systemImage)
                        .foregroundStyle(type.color)
                        .frame(width: 24)
                    Text(type.csvKey)
                        .font(.system(.body, design: .monospaced))
                    Spacer()
                    Text(type.rawValue)
                        .foregroundStyle(.secondary)
                }
            }
        } header: {
            Text("Exercise Types")
        } footer: {
            Text("Use the short key (left column) in your CSV. \"cross\" is also accepted as an alias for \"other\". Unrecognized types default to \"other\".")
        }
    }

    private var durationSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                helpRow("40m", detail: "40 minutes")
                helpRow("1h 30m", detail: "1 hour 30 minutes")
                helpRow("2h 2m 30s", detail: "2 hours 2 minutes 30 seconds")
                helpRow("90s", detail: "90 seconds")
                helpRow("1800", detail: "1800 seconds (no unit = seconds)")
            }
        } header: {
            Text("Duration Format")
        } footer: {
            Text("Use h (hours), m (minutes), and s (seconds) in any combination. Units can appear in any order. A plain number without a unit is treated as seconds. Decimal values are rounded down.")
        }
    }

    private var distanceSection: some View {
        Section {
            Text("Enter distance as a number (e.g., 4 or 3.5). The unit (miles or kilometers) is chosen during import, not in the CSV.")
                .font(.caption)
                .foregroundStyle(.secondary)
        } header: {
            Text("Distance")
        }
    }

    private var optionalFieldsSection: some View {
        Section {
            VStack(alignment: .leading, spacing: 6) {
                Text("**notes** \u{2014} free text, leave blank if none")
                    .font(.caption)
                Text("**feeling** \u{2014} 1\u{2013}5 integer (1 = Very Weak, 5 = Very Strong), leave blank for unrated")
                    .font(.caption)
                Text("**perceived_exertion** \u{2014} 1\u{2013}10 integer (1 = Very Light, 10 = Maximum), leave blank for unrated")
                    .font(.caption)
            }
        } header: {
            Text("Optional Fields")
        } footer: {
            Text("All three can be left empty, and a rating of 0 is read as unrated. You can also omit them entirely by having only 5, 6, or 7 columns per row.")
        }
    }

    private var exampleSection: some View {
        Section {
            Text("""
            date,name,type,duration,distance,notes,feeling,perceived_exertion
            8/4/2025,Easy Run,easy,40m,4,,4,5
            2025-09-14,5k,race,22m,3.5,,1,10
            2/21/2026,,long,2h 2m 30s,14,,,
            """)
            .font(.system(.caption2, design: .monospaced))
        } header: {
            Text("Example")
        } footer: {
            Text("The third row has no name \u{2014} it will be imported as \"Long Run\" based on the type \u{2014} and no ratings.")
        }
    }

    // MARK: - Helpers

    private func helpRow(_ label: String, detail: String) -> some View {
        HStack {
            Text(label)
                .font(.system(.caption, design: .monospaced))
                .frame(width: 120, alignment: .leading)
            Text(detail)
                .font(.caption)
                .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    CSVImportHelpView()
}
