import CitadelClient
import Foundation

/// One day of a project's cumulative flow (API minor 18), the server's states folded into the chart's four bands.
struct CfdPoint: Equatable, Sendable {
    var day: Date
    var done: Int
    var review: Int
    /// In progress and blocked.
    var active: Int
    /// To do and backlog.
    var todo: Int

    var total: Int { done + review + active + todo }
}

extension CfdPoint {
    init?(_ day: Schemas.CfdDay) {
        guard let date = ProjectLogic.day(day.day) else { return nil }
        let counts = day.counts.additionalProperties
        func count(_ states: String...) -> Int { states.reduce(0) { $0 + Int(counts[$1] ?? 0) } }
        self.init(
            day: date, done: count("done"), review: count("in_review"), active: count("in_progress", "blocked"),
            todo: count("todo", "backlog"))
    }
}

/// What a run on a project is given, rendered (`GET /projects/{id}/profile/preview`).
struct ProfilePreviewInfo: Equatable, Sendable {
    var text: String
    var bytes: Int64
    var budgetBytes: Int64
    /// Sections the budget left out.
    var dropped: [String]
}

extension ProfilePreviewInfo {
    init(_ preview: Schemas.ProfilePreview) {
        self.init(
            text: preview.text, bytes: preview.bytes, budgetBytes: preview.budgetBytes, dropped: preview.dropped)
    }
}

/// What "Add repository"'s check found out about a repo before anything is saved (API minor 18).
struct RepoProbe: Equatable, Sendable {
    /// The URL answers.
    var reachable: Bool
    /// The token can push a branch and open a PR; `nil` when none was given or the server could not tell.
    var canPush: Bool?
    var defaultBranch: String?
    /// What it is built with, "Rust · Node"; empty when unknown.
    var stack: String
    var note: String?
    var build: String?
    var test: String?
    var lint: String?
    var format: String?

    /// Safe to add: it answers and its token, when it was checked, can push.
    var passes: Bool { reachable && canPush != false }
}

extension RepoProbe {
    init(_ probed: Schemas.Probed) {
        self.init(
            reachable: probed.reachable, canPush: probed.canPush, defaultBranch: probed.defaultBranch.nonEmpty,
            stack: probed.stack, note: probed.note.nonEmpty, build: probed.commands.build.nonEmpty,
            test: probed.commands.test.nonEmpty, lint: probed.commands.lint.nonEmpty,
            format: probed.commands.format.nonEmpty)
    }
}
