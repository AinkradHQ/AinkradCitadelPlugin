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
