import Foundation

/// A step of the issue state machine, as `POST /issues/{id}/transition` takes it (ported from AinkradQuest's
/// `BoardLogic`).
enum BoardStep: Equatable, Sendable {
    case ready, start, done, approve
    case submitForReview(reviewer: Int64)
    case requestChanges(assignee: Int64?)
    case reopen(next: Int64?)
}

/// Why a drop was refused, in the words a toast shows.
struct BoardRefusal: Error, Equatable, Sendable {
    var message: String
}

/// Where a dragged backlog row lands (`POST /issues/{id}/move`).
enum RankPlace: Equatable, Sendable {
    case top
    case before(Int64)
    case after(Int64)
}

/// The project tabs' pure rules, ported from AinkradQuest (`BoardLogic`, `BacklogLogic`, `SprintLogic`,
/// `ServerInsights`) onto the plugin's `WorkItem`.
enum ProjectLogic {
    /// The board's four columns, in order.
    static let columns = ["todo", "in_progress", "in_review", "done"]
    /// The flow bar's states, in the prototype's order.
    static let flowStates = ["todo", "in_progress", "review", "blocked", "done"]

    static func flowState(_ state: String) -> String? {
        switch state {
        case "backlog", "todo": "todo"
        case "in_progress": "in_progress"
        case "in_review": "review"
        case "blocked": "blocked"
        case "done": "done"
        default: nil
        }
    }

    static func title(_ state: String) -> String {
        switch state {
        case "backlog": "Backlog"
        case "todo": "To do"
        case "in_progress": "In progress"
        case "in_review", "review": "In review"
        case "blocked": "Blocked"
        case "done": "Done"
        case "cancelled": "Cancelled"
        default: state.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }

    /// Lower rank first; id breaks a tie so the order is stable.
    static func ranked(_ items: [WorkItem]) -> [WorkItem] {
        items.sorted { ($0.rank, $0.id) < ($1.rank, $1.id) }
    }

    /// The step that moves `item` into board column `target`; `reviewer` is the project's QA agent.
    static func step(for item: WorkItem, to target: String, reviewer: Int64?) -> Result<BoardStep, BoardRefusal> {
        if item.isBlocked, target != "in_progress" {
            return .failure(BoardRefusal(message: "\(item.key) is blocked — clear its blocker first."))
        }
        switch (item.state, target) {
        case ("backlog", "todo"): return .success(.ready)
        case ("backlog", "in_progress"), ("todo", "in_progress"): return .success(.start)
        case ("in_progress", "in_review"):
            guard let reviewer else {
                return .failure(BoardRefusal(message: "No QA agent to review \(item.key) — hire one first."))
            }
            return .success(.submitForReview(reviewer: reviewer))
        case ("in_progress", "done"): return .success(.done)
        case ("in_review", "done"): return .success(.approve)
        case ("in_review", "in_progress"): return .success(.requestChanges(assignee: item.ownerAgentID))
        case ("done", "todo"), ("cancelled", "todo"): return .success(.reopen(next: item.ownerAgentID))
        default:
            return .failure(
                BoardRefusal(
                    message: "Citadel has no step from \(title(item.state)) to \(title(target)) for \(item.key)."))
        }
    }

    /// Refuses a drop into a column already at its WIP limit (the server's 409, checked first).
    static func wipRefusal(moving item: WorkItem, into target: String, items: [WorkItem], limits: [String: Int])
        -> String?
    {
        guard let limit = limits[target], item.state != target else { return nil }
        let count = items.filter { $0.state == target }.count
        guard count >= limit else { return nil }
        return "\(title(target)) is full (\(count) / \(limit)). Finish or move one out before starting \(item.key)."
    }

    /// The move for dropping `item` at `index` of `order` (the list as shown, the item still in it).
    static func place(_ item: Int64, at index: Int, in order: [WorkItem]) -> RankPlace? {
        guard let from = order.firstIndex(where: { $0.id == item }) else { return nil }
        var rest = order
        rest.remove(at: from)
        let slot = min(max(0, index > from ? index - 1 : index), rest.count)
        if slot == from { return nil }
        if rest.isEmpty { return .top }
        return slot < rest.count ? .before(rest[slot].id) : .after(rest[rest.count - 1].id)
    }

    /// The ideal burndown: `points` on the first day to zero on the last, one value per day.
    static func ideal(points: Int, days: Int) -> [Double] {
        guard days > 1 else { return [Double(points)] }
        return (0..<days).map { Double(points) * (1 - Double($0) / Double(days - 1)) }
    }

    /// The `p`th percentile (0…1) by nearest rank.
    static func percentile(_ values: [Double], _ p: Double) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let rank = Int((p * Double(sorted.count)).rounded(.up)) - 1
        return sorted[min(max(rank, 0), sorted.count - 1)]
    }

    static func day(_ text: String) -> Date? {
        try? Date(text, strategy: Date.ISO8601FormatStyle().year().month().day())
    }

    static func dayString(_ date: Date) -> String {
        date.formatted(Date.ISO8601FormatStyle().year().month().day())
    }
}
