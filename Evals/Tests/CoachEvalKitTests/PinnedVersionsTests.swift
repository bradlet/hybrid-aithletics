//
//  PinnedVersionsTests.swift
//  CoachEvalKitTests
//
//  The evals only measure the app if they run the app's exact model stack.
//  SwiftPM resolves each package independently, so Evals/Package.resolved can
//  drift from the Xcode project's pins (it once picked up swift-jinja 3.0.0,
//  which renders the chat template, while the app used 2.5.1). This fails
//  when that happens.
//

import Foundation
import Testing

struct PinnedVersionsTests {

    /// Packages that shape what the model sees or how it runs.
    private static let modelStack = [
        "mlx-swift", "mlx-swift-lm", "swift-transformers", "swift-jinja", "swift-huggingface",
    ]

    /// The repository root, from this file's location.
    private static let repoRoot = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent() // CoachEvalKitTests
        .deletingLastPathComponent() // Tests
        .deletingLastPathComponent() // Evals
        .deletingLastPathComponent()

    /// Identity → resolved revision from a `Package.resolved` file.
    private static func revisions(_ relativePath: String) throws -> [String: String] {
        let data = try Data(contentsOf: repoRoot.appendingPathComponent(relativePath))
        let json = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        let pins = try #require(json["pins"] as? [[String: Any]])
        return pins.reduce(into: [:]) { result, pin in
            guard let identity = pin["identity"] as? String,
                  let state = pin["state"] as? [String: Any],
                  let revision = state["revision"] as? String else { return }
            result[identity] = revision
        }
    }

    @Test(arguments: ["Evals/Package.resolved", "Packages/AICoachRuntime/Package.resolved"])
    func modelStackMatchesTheApp(_ resolvedFile: String) throws {
        let app = try Self.revisions(
            "Hybrid AIthletics.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"
        )
        let other = try Self.revisions(resolvedFile)
        for package in Self.modelStack {
            #expect(other[package] != nil, "\(package) missing from \(resolvedFile)")
            #expect(other[package] == app[package], "\(package) in \(resolvedFile) differs from the app's pin")
        }
    }
}
