import AinkradAppKit
import Foundation
import Observation

/// Screen 12 Requirements: the requirement list, the open thread with the CEO and its live plan.
@MainActor
@Observable
final class RequirementsPage {
    /// Loaded once the screen first opens.
    var isLoaded = false
    var filter: RequirementFilter = .open
    /// The open requirement; `nil` is the first in the list.
    var selectedID: Int64?
    /// Each opened requirement's thread and plan.
    var threads: [Int64: RequirementThread] = [:]
    var plans: [Int64: PlanTree] = [:]
    /// The composer's To chip was cleared: the next message goes to the owner (decision #44).
    var targetCleared = false
}

enum RequirementFilter: String, CaseIterable, Hashable {
    case open, needsYou, done

    var title: String {
        switch self {
        case .open: "Open"
        case .needsYou: "Needs you"
        case .done: "Done"
        }
    }
}

/// One requirement's conversation with its owner (GET /requirements/{id}/thread), oldest first.
struct RequirementThread: Equatable, Sendable {
    var requirementID: Int64
    /// Who a message to the owner wakes: the CEO, the PO after hand-off (decision #45).
    var ownerAgentID: Int64?
    /// What a post answers unless the chip is cleared: the newest open question (decision #44).
    var toQuestionID: Int64?
    var items: [ThreadItem]

    var openQuestions: [QuestionInfo] {
        items.compactMap { if case .question(let q, _) = $0, q.isOpen { q } else { nil } }
    }
}

/// One thing in a requirement thread.
enum ThreadItem: Equatable, Sendable, Identifiable {
    /// A message: yours (`agentID == nil`) or an agent's, on `issueID`.
    case message(CommentInfo, at: Date)
    /// An agent's question: a card while open, a receipt once answered (with your answer).
    case question(QuestionInfo, answer: String?)
    case approval(ApprovalInfo, at: Date)
    case artifact(ArtifactInfo)

    var id: String {
        switch self {
        case .message(let c, _): "m\(c.id)"
        case .question(let q, _): "q\(q.id)"
        case .approval(let a, _): "a\(a.id)"
        case .artifact(let a): "f\(a.id)"
        }
    }
}

/// A thread line as drawn: consecutive artifacts share one two-column grid under the message they follow.
enum HubLine: Identifiable, Equatable {
    case item(ThreadItem)
    case artifacts([ArtifactInfo])

    var id: String {
        switch self {
        case .item(let item): item.id
        case .artifacts(let list): "g\(list.first?.id ?? 0)"
        }
    }

    static func lines(_ items: [ThreadItem]) -> [HubLine] {
        var lines: [HubLine] = []
        for item in items {
            if case .artifact(let artifact) = item {
                if case .artifacts(let list) = lines.last {
                    lines[lines.count - 1] = .artifacts(list + [artifact])
                    continue
                }
                lines.append(.artifacts([artifact]))
            } else {
                lines.append(.item(item))
            }
        }
        return lines
    }
}

/// Who the composer sends to: the open question's asker (on its issue), or the requirement's owner.
enum ComposerTarget: Equatable {
    case question(QuestionInfo)
    case owner(agentID: Int64?)

    /// The thread post's fields: the question it answers, or `to_owner`.
    var post: (questionID: Int64?, toOwner: Bool) {
        switch self {
        case .question(let q): (q.id, false)
        case .owner: (nil, true)
        }
    }
}

extension RequirementThread {
    /// Decision #44: the newest open question (the server's `to_question_id`, else the newest asked), unless the
    /// chip was cleared — then the owner.
    func target(cleared: Bool) -> ComposerTarget {
        let open = openQuestions
        if !cleared, let question = open.first(where: { $0.id == toQuestionID }) ?? open.max(by: Self.older) {
            return .question(question)
        }
        return .owner(agentID: ownerAgentID)
    }

    private static func older(_ a: QuestionInfo, _ b: QuestionInfo) -> Bool {
        (a.askedAt, a.id) < (b.askedAt, b.id)
    }

    /// After a post answered `question`: its card becomes a receipt at once (the event refreshes the rest).
    mutating func answered(_ question: Int64, with answer: String) {
        for (index, item) in items.enumerated() {
            guard case .question(var q, _) = item, q.id == question else { continue }
            q.state = "answered"
            items[index] = .question(q, answer: answer)
        }
        if toQuestionID == question { toQuestionID = openQuestions.max(by: Self.older)?.id }
    }
}

/// A requirement's live plan (GET /requirements/{id}/tree).
struct PlanTree: Equatable, Sendable {
    var points: Int
    var donePoints: Int
    var percent: Int
    var tasks: Int
    var doneTasks: Int
    var eta: String?
    var pointsPerDay: Double
    var tokens: Int64
    var costMicros: Int64
    /// Points left per day, oldest first.
    var burndown: [(day: String, left: Int)]
    var epics: [PlanEpic]
    /// Tasks under no epic.
    var other: [PlanTask]
    var diff: PlanDiffInfo?
    /// The requirement's intake issue: messages on it are "with the CEO", others "on CIT-61".
    var intakeIssueID: Int64?
    /// The plan version approved (`plan_version`); 0 while unapproved.
    var planVersion: Int

    var allTasks: [PlanTask] { epics.flatMap(\.tasks) + other }
    var inReview: Int { allTasks.filter { $0.state == "in_review" }.count }

    static func == (a: PlanTree, b: PlanTree) -> Bool {
        a.points == b.points && a.donePoints == b.donePoints && a.percent == b.percent && a.tasks == b.tasks
            && a.doneTasks == b.doneTasks && a.eta == b.eta && a.tokens == b.tokens && a.costMicros == b.costMicros
            && a.burndown.map(\.day) == b.burndown.map(\.day) && a.burndown.map(\.left) == b.burndown.map(\.left)
            && a.epics == b.epics && a.other == b.other && a.diff == b.diff && a.planVersion == b.planVersion
    }
}

struct PlanEpic: Identifiable, Equatable, Sendable {
    let id: Int64
    var projectID: Int64
    var title: String
    var points: Int
    var donePoints: Int
    var tasks: [PlanTask]
    /// `CIT-E3`, once the project's epics were read.
    var key: String? = nil

    /// ◆ once any task moved, ◇ while every task is still to do.
    var started: Bool { tasks.contains { !["todo", "backlog"].contains($0.state) } }
}

struct PlanTask: Identifiable, Equatable, Sendable {
    var id: Int64 { issueID }
    var issueID: Int64
    var key: String
    var title: String
    var points: Int?
    var state: String
    var assigneeAgentID: Int64?
    var prs: Int64
    var timeSecs: Int64
    var tokens: Int64
    var sprintID: Int64?
}

/// What changed since the plan was approved: "+1 task since approval (CIT-60, +3 pts) · diff vs v1".
struct PlanDiffInfo: Equatable, Sendable {
    var version: Int
    var added: [(key: String, points: Int?)]
    var removed: [(key: String, points: Int?)]
    var pointsApproved: Int
    var pointsNow: Int

    static func == (a: PlanDiffInfo, b: PlanDiffInfo) -> Bool {
        a.version == b.version && a.added.map(\.key) == b.added.map(\.key)
            && a.removed.map(\.key) == b.removed.map(\.key) && a.pointsNow == b.pointsNow
    }

    /// `nil` when nothing changed since approval.
    var summary: String? {
        guard !added.isEmpty || !removed.isEmpty else { return nil }
        var parts: [String] = []
        if !added.isEmpty {
            let pts = added.compactMap(\.points).reduce(0, +)
            parts.append(
                "+\(added.count) task\(added.count == 1 ? "" : "s") since approval (\(added.map(\.key).joined(separator: ", ")), +\(pts) pts)"
            )
        }
        if !removed.isEmpty {
            parts.append(
                "−\(removed.count) task\(removed.count == 1 ? "" : "s") (\(removed.map(\.key).joined(separator: ", ")))"
            )
        }
        return parts.joined(separator: " · ")
    }
}

/// A task's state as the tree draws it: ✓ done, ▶ running, ⑂ in review, ◐ waiting on you, ● blocked, ○ to do.
enum TaskGlyph: Equatable {
    case done, running, review, waiting, blocked, todo

    init(state: String, asksYou: Bool) {
        if asksYou, state != "done" {
            self = .waiting
            return
        }
        switch state {
        case "done": self = .done
        case "in_progress": self = .running
        case "in_review": self = .review
        case "blocked": self = .blocked
        default: self = .todo
        }
    }

    var glyph: String {
        switch self {
        case .done: "✓"
        case .running: "▶"
        case .review: "⑂"
        case .waiting: "◐"
        case .blocked: "●"
        case .todo: "○"
        }
    }

    var tone: AinkradChartTone {
        switch self {
        case .done: .success
        case .running, .review: .accentSecondary
        case .waiting: .warning
        case .blocked: .danger
        case .todo: .muted
        }
    }
}

extension CompanyModel {
    /// The list for a filter: open (planning → plan to approve → in progress), needing you, or done; newest first.
    func requirementList(_ filter: RequirementFilter) -> [RequirementInfo] {
        let sorted = requirements.filter { $0.state != "cancelled" }.sorted { $0.id > $1.id }
        switch filter {
        case .open: return sorted.filter { $0.state != "done" }
        case .needsYou: return sorted.filter { $0.state != "done" && waitingCount($0) > 0 }
        case .done: return sorted.filter { $0.state == "done" }
        }
    }

    /// Questions and approvals waiting on you inside a requirement (the list's yellow count).
    func waitingCount(_ requirement: RequirementInfo) -> Int {
        let asks = questions.filter { $0.isOpen && $0.requirementID == requirement.id }.count
        let plans = approvals.filter { $0.fields["requirement"] == String(requirement.id) }.count
        return asks + plans
    }

    /// "CEO · 5 / 31 pts", "PO Mira · 13 pts", "CEO drafting · no work yet".
    func requirementSubtitle(_ requirement: RequirementInfo) -> String {
        let owner = ownerWord(requirement.ownerAgentID)
        switch requirement.state {
        case "planning": return "\(owner) drafting · no work yet"
        case "plan_review": return "\(owner) · \(requirement.points) pts"
        case "done": return "\(owner) · \(requirement.points) pts"
        default: return "\(owner) · \(requirement.donePoints) / \(requirement.points) pts"
        }
    }

    /// "CEO", or "PO Mira" once the CEO handed it to a team (decision #45).
    func ownerWord(_ id: Int64?) -> String {
        guard let owner = agent(id) else { return "CEO" }
        return owner.orgRole == "ceo" ? "CEO" : Wording.name(owner.role, owner.name, separator: " ")
    }

    /// "Aldric (CEO)", "Mira (PO)".
    func ownerName(_ id: Int64?) -> String {
        guard let owner = agent(id) ?? ceo else { return "the CEO" }
        return Wording.parenthesized(owner.name, owner.orgRole == "ceo" ? "CEO" : owner.role)
    }

    /// A tree task's glyph: waiting on you when its issue has an open question.
    func glyph(_ task: PlanTask) -> TaskGlyph {
        TaskGlyph(state: task.state, asksYou: questions.contains { $0.isOpen && $0.issueID == task.issueID })
    }

    /// The faint line under a task: "done · 1h40m · 96k tok", "2 PRs · in review", "asks you · 2 repos".
    func taskMeta(_ task: PlanTask) -> String? {
        var parts: [String] = []
        switch glyph(task) {
        case .done: parts = ["done", Fmt.duration(TimeInterval(task.timeSecs)), "\(Fmt.tokens(task.tokens)) tok"]
        case .review: parts = ["\(task.prs) PR\(task.prs == 1 ? "" : "s")", "in review"]
        case .waiting: parts = ["asks you"]
        case .blocked: parts = ["blocked"]
        default: return nil
        }
        if let repos = issueRepos[task.issueID], repos.count > 1, task.prs == 0 { parts.append("\(repos.count) repos") }
        return parts.joined(separator: " · ")
    }

    /// "Kestrel (Dev)".
    func askerName(_ id: Int64) -> String {
        guard let agent = agent(id) else { return "An agent" }
        return "\(agent.name) (\(agent.role.prefix(1).uppercased() + agent.role.dropFirst()))"
    }
}
