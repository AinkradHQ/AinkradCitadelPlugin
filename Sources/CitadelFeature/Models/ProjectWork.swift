import CitadelClient
import Foundation

extension Schemas.IssueKind: OpenWord {}
extension Schemas.EpicStatus: OpenWord {}

/// One work item of a project as the board, backlog and item drawer read it (`listProjectIssues`).
struct WorkItem: Identifiable, Equatable, Sendable {
    let id: Int64
    var key: String
    var title: String
    var projectID: Int64
    /// `backlog`, `todo`, `in_progress`, `in_review`, `blocked`, `done`, `cancelled`.
    var state: String
    /// `story`, `task`, `bug`, `subtask` (the server has no chore / spike yet).
    var kind = "task"
    /// The server's one priority flag; the board reads it as High.
    var priority = false
    var points: Int?
    var epicID: Int64?
    var sprintID: Int64?
    var ownerAgentID: Int64?
    var requirementID: Int64?
    var checkoutRunID: Int64?
    var rank: Double = 0
    var body = ""
    var labels: [String] = []

    var isBlocked: Bool { state == "blocked" }
    var isDone: Bool { state == "done" }
    var isOpen: Bool { state != "done" && state != "cancelled" }

    /// The board column it sits in: blocked work stays In progress with ⚑ (the prototype's way).
    var column: String {
        switch state {
        case "backlog", "todo": "todo"
        case "in_progress", "blocked": "in_progress"
        case "in_review": "in_review"
        case "done": "done"
        default: "cancelled"
        }
    }
}

struct EpicInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var key: String
    var title: String
    var status: String
}

/// A sprint with its dates and goal.
struct SprintDetail: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    var goal: String
    /// `planned`, `active`, `closed`.
    var state: String
    var startsOn: Date?
    var endsOn: Date?

    /// "day 6 of 10": working days counted as calendar days, as the server stores the range.
    func day(now: Date = Date()) -> (day: Int, of: Int)? {
        guard let startsOn, let endsOn else { return nil }
        let calendar = Calendar.current
        let length = (calendar.dateComponents([.day], from: startsOn, to: endsOn).day ?? 0) + 1
        let day = (calendar.dateComponents([.day], from: startsOn, to: now).day ?? 0) + 1
        return (min(max(day, 1), length), max(length, 1))
    }

    /// "Nov 3 → Nov 14".
    var range: String {
        let style = Date.FormatStyle().month(.abbreviated).day()
        return [startsOn, endsOn].map { $0?.formatted(style) ?? "—" }.joined(separator: " → ")
    }
}

/// A sprint's points and burndown (`getSprintReport`).
struct SprintReportInfo: Equatable, Sendable {
    var sprintID: Int64
    var committed: Int
    var completed: Int
    var capacity: Int?
    /// Points left, one per day from the first.
    var burndown: [Int]

    var left: Int { max(0, committed - completed) }
    var fraction: Double { committed > 0 ? Double(completed) / Double(committed) : 0 }
}

/// One closed sprint's points (`getVelocity`).
struct VelocityPoint: Equatable, Sendable {
    var sprintID: Int64
    var committed: Int
    var completed: Int
}

/// Everything the project page's tabs show beyond the profile.
struct ProjectWork: Equatable, Sendable {
    var items: [WorkItem] = []
    var epics: [EpicInfo] = []
    /// Oldest first.
    var sprints: [SprintDetail] = []
    var report: SprintReportInfo?
    var velocity: [VelocityPoint] = []
    var velocityAverage: Double?
    /// Each agent's points per sprint on this project (`getTeamCapacity`).
    var capacity: [Int64: Int] = [:]
    /// Days from start to done of the recently finished items.
    var cycleDays: [Double] = []
    /// Items done per week, oldest first, with the week's label (`W43`).
    var throughput: [(week: String, done: Int)] = []
    /// WIP limits per state.
    var wip: [String: Int] = [:]
    /// What this month's runs on its issues cost (`getTaskCosts` summed: the server has no project scope).
    var monthSpend: Int64?

    static func == (a: Self, b: Self) -> Bool {
        a.items == b.items && a.epics == b.epics && a.sprints == b.sprints && a.report == b.report
            && a.velocity == b.velocity && a.capacity == b.capacity && a.cycleDays == b.cycleDays
            && a.throughput.map(\.done) == b.throughput.map(\.done) && a.wip == b.wip && a.monthSpend == b.monthSpend
    }

    var active: SprintDetail? { sprints.last { $0.state == "active" } }
    var next: SprintDetail? { sprints.first { $0.state == "planned" } }
    var open: [WorkItem] { items.filter(\.isOpen) }

    func items(in sprint: Int64?) -> [WorkItem] { items.filter { $0.sprintID == sprint } }
    func epic(_ id: Int64?) -> EpicInfo? { id.flatMap { id in epics.first { $0.id == id } } }

    /// The board's items: the active sprint's (every open item on Kanban).
    var boardItems: [WorkItem] {
        guard let active else { return items.filter { $0.state != "cancelled" } }
        return items.filter { $0.sprintID == active.id && $0.state != "cancelled" }
    }

    /// Unsprinted open items: the Backlog tab's count.
    var backlog: [WorkItem] { ProjectLogic.ranked(items.filter { $0.isOpen && $0.sprintID == nil }) }

    /// Count per flow state, in the prototype's order (To do, In progress, Review, Blocked, Done).
    var flow: [(state: String, count: Int)] {
        ProjectLogic.flowStates.map { state in
            (state, items.filter { ProjectLogic.flowState($0.state) == state }.count)
        }
    }

    /// An epic's items done of all, and points done of all.
    func progress(_ epic: Int64) -> (done: Int, of: Int, donePoints: Int, points: Int) {
        let mine = items.filter { $0.epicID == epic && $0.state != "cancelled" }
        let done = mine.filter(\.isDone)
        return (
            done.count, mine.count, done.reduce(0) { $0 + ($1.points ?? 0) }, mine.reduce(0) { $0 + ($1.points ?? 0) }
        )
    }
}

extension WorkItem {
    init(_ issue: Schemas.Issue) {
        var owner: Int64?
        if case .agent(let agent) = issue.owner { owner = agent.agentId }
        self.init(
            id: issue.id, key: issue.key, title: issue.title, projectID: issue.projectId, state: issue.state.word,
            kind: issue.kind.word, priority: issue.priority, points: issue.points.map(Int.init), epicID: issue.epicId,
            sprintID: issue.sprintId, ownerAgentID: owner, requirementID: issue.requirementId,
            checkoutRunID: issue.checkoutRunId, rank: issue.rank, body: issue.body, labels: issue.labels.map(\.name))
    }
}

extension EpicInfo {
    init(_ epic: Schemas.Epic) {
        self.init(id: epic.id, key: epic.key, title: epic.title, status: epic.status.word)
    }
}

extension SprintDetail {
    init(_ sprint: Schemas.Sprint) {
        self.init(
            id: sprint.id, name: sprint.name, goal: sprint.goal, state: sprint.state.word,
            startsOn: sprint.startsOn.flatMap(ProjectLogic.day), endsOn: sprint.endsOn.flatMap(ProjectLogic.day))
    }
}

extension SprintReportInfo {
    init(_ report: Schemas.SprintReport) {
        self.init(
            sprintID: report.sprintId, committed: Int(report.committed ?? 0), completed: Int(report.completed),
            capacity: report.capacity.map(Int.init),
            burndown: report.burndown.sorted { $0.day < $1.day }.map { Int($0.left) })
    }
}
