import Foundation
import Observation

/// Screen 07's list state: the tab, and what you have seen. The server keeps no read marker, so "unread" is
/// activity since this window opened or since you last opened the thread.
@MainActor
@Observable
final class ThreadsPage {
    var filter: ThreadFilter = .all
    /// Activity before this counts as read.
    var baseline = Date()
    var seen: [ThreadKey: Date] = [:]

    func isUnread(_ thread: ThreadSummary) -> Bool {
        thread.at > max(baseline, seen[thread.key] ?? .distantPast)
    }
}

enum ThreadFilter: String, CaseIterable, Hashable {
    case all, asksYou, unread

    var title: String {
        switch self {
        case .all: "All"
        case .asksYou: "Asks you"
        case .unread: "Unread"
        }
    }
}
