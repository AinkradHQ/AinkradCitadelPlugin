import AinkradAppKit
import CoreGraphics
import Foundation

/// The org chart's six state buckets (prototype `org.js` ORG_STATE): what the legend counts, the ring a bubble
/// wears and the status chip's dot.
enum OrgBucket: String, CaseIterable, Hashable {
    case busy, warn, bad, idle, away, pending

    init(_ agent: AgentInfo) {
        if agent.isHirePending {
            self = .pending
        } else if agent.isPaused {
            self = .away
        } else {
            switch agent.figure {
            case .working, .thinking, .loading: self = .busy
            case .listening: self = .warn
            case .confused, .error: self = .bad
            case .sleepy, .rest: self = .away
            default: self = .idle
            }
        }
    }

    var label: String {
        switch self {
        case .busy: "Working"
        case .warn: "Waiting"
        case .bad: "Blocked"
        case .idle: "Idle"
        case .away: "Paused"
        case .pending: "Pending hire"
        }
    }
}

/// What the org filters keep bright; the rest dims in place so the chart keeps its shape.
enum OrgFilter: String, CaseIterable, Hashable {
    case all = "All"
    case working = "Working"
    case waiting = "Waiting"
    case paused = "Paused"

    func matches(_ agent: AgentInfo) -> Bool {
        let bucket = OrgBucket(agent)
        switch self {
        case .all: return true
        case .working: return bucket == .busy
        case .waiting: return bucket == .warn || bucket == .bad
        case .paused: return agent.isPaused || agent.isHirePending
        }
    }

    var icon: String {
        switch self {
        case .all: "person.2"
        case .working: "bolt"
        case .waiting: "clock"
        case .paused: "pause"
        }
    }
}

extension CompanyModel {
    /// A department's head: the one the server names (`head_agent_id`, API minor 17), else the agent outside every
    /// team (not the CEO) whose direct reports are seated in it — the chain of command says who it is.
    func head(of department: DepartmentInfo) -> AgentInfo? {
        if let stored = department.headAgentID.flatMap({ agents[$0] }) { return stored }
        let seated = Set(departments.flatMap(\.agentIDs))
        let members = Set(department.agentIDs)
        return agents.values.filter { candidate in
            candidate.orgRole != "ceo" && !seated.contains(candidate.id)
                && members.contains { agents[$0]?.reportsTo == candidate.id }
        }.min { $0.id < $1.id }
    }

    func lead(of team: TeamInfo) -> AgentInfo? {
        team.seats.first { $0.teamRole == "team_lead" }.flatMap { agents[$0.agentID] }
    }

    func team(of agent: Int64) -> (DepartmentInfo, TeamInfo)? {
        for department in departments {
            if let team = department.teams.first(where: { $0.seats.contains { $0.agentID == agent } }) {
                return (department, team)
            }
        }
        return nil
    }

    func headedDepartment(of agent: Int64) -> DepartmentInfo? {
        departments.first { head(of: $0)?.id == agent }
    }

    func project(of team: TeamInfo) -> ProjectInfo? { projects.first { $0.teamID == team.id } }

    /// Who reports to `agent`.
    func reports(of agent: Int64) -> [AgentInfo] {
        agents.values.filter { $0.reportsTo == agent && $0.id != agent }.sorted { $0.id < $1.id }
    }

    /// `S4 · day 6`, `Kanban`, or the project's flow.
    func cadence(of team: TeamInfo, now: Date = Date()) -> (text: String, isSprint: Bool)? {
        guard let project = project(of: team) else { return nil }
        if let sprint, sprint.projectKey == project.key {
            let day = sprint.startsOn.map {
                (Calendar.current.dateComponents([.day], from: $0, to: now).day ?? 0) + 1
            }
            return ("\(sprint.name)\(day.map { " · day \($0)" } ?? "")", true)
        }
        return (project.mode == "kanban" ? "Kanban" : "Scrum", false)
    }

    /// The agent's place: `Head of Engineering`, `★ Lead · Citadel Core`, `Engineering › Citadel Core`.
    func title(of agent: AgentInfo) -> String {
        if let department = headedDepartment(of: agent.id) { return "Head of \(department.name)" }
        if let (department, team) = team(of: agent.id) {
            return lead(of: team)?.id == agent.id ? "★ Lead · \(team.name)" : "\(department.name) › \(team.name)"
        }
        return agent.orgRole == "ceo" ? "Company" : "Unseated"
    }

    /// The pending hire approval of a proposed agent.
    func hireApproval(of agent: Int64) -> ApprovalInfo? {
        approvals.first { $0.kind == "hire_agent" && $0.agentID == agent }
    }

    /// The agent's month budget (tokens; decision 1 of the parity plan).
    func monthBudget(of agent: Int64) -> BudgetInfo? {
        budgets.first { $0.scope == "agent:\(agent)" && $0.period == "month" }
    }

    /// Issues the agent moves next that it is not working on now: "Next in its queue".
    func queue(of agent: Int64) -> [IssueInfo] {
        let live = currentRun(of: agent).flatMap { $0.isLive ? $0.issueID : nil }
        return issues.values.filter {
            $0.nextActor == .agent(agent) && $0.id != live && !["done", "cancelled"].contains($0.state)
        }.sorted { $0.id < $1.id }
    }

    /// Open issues the agent holds (Reassign its work…).
    func openWork(of agent: Int64) -> [IssueInfo] {
        issues.values.filter { $0.nextActor == .agent(agent) && !["done", "cancelled"].contains($0.state) }
            .sorted { $0.id < $1.id }
    }
}

/// The chart's world layout in points at zoom 1 (prototype `org.js` OL / orgLayout): the CEO on top, departments
/// left to right, each with its teams centred underneath. Computed, never measured.
struct OrgLayout: Equatable {
    static let cell: CGFloat = 76
    static let rowH: CGFloat = 92
    static let pad: CGFloat = 16
    static let head: CGFloat = 46
    static let cols = 4
    static let gapT: CGFloat = 28
    static let gapD: CGFloat = 72
    static let ceoW: CGFloat = 280
    static let ceoH: CGFloat = 76
    static let depW: CGFloat = 264
    static let depH: CGFloat = 68
    static let y1: CGFloat = 150
    static let y2: CGFloat = 300

    struct Team: Equatable {
        let id: Int64
        var x: CGFloat
        let width: CGFloat
        let height: CGFloat
        let cols: Int
        var cx: CGFloat { x + width / 2 }
    }

    struct Department: Equatable {
        let id: Int64
        let x: CGFloat
        let width: CGFloat
        let teams: [Team]
        var cx: CGFloat { x + width / 2 }
    }

    let departments: [Department]
    let width: CGFloat
    let height: CGFloat
    var cx: CGFloat { width / 2 }

    init(_ departments: [DepartmentInfo]) {
        var x: CGFloat = 0
        var laid: [Department] = []
        for department in departments {
            let teams = department.teams.map { team -> Team in
                let n = team.seats.count + 1
                let cols = min(Self.cols, n)
                let rows = Int((Double(n) / Double(cols)).rounded(.up))
                return Team(
                    id: team.id, x: 0, width: CGFloat(cols) * Self.cell + Self.pad * 2,
                    height: Self.head + CGFloat(rows) * Self.rowH + Self.pad - 8, cols: cols)
            }
            let teamsWidth = teams.reduce(0) { $0 + $1.width } + Self.gapT * CGFloat(max(0, teams.count - 1))
            let width = max(teamsWidth, Self.depW)
            var tx = x + width / 2 - teamsWidth / 2
            let placed = teams.map { team -> Team in
                var team = team
                team.x = tx
                tx += team.width + Self.gapT
                return team
            }
            laid.append(Department(id: department.id, x: x, width: width, teams: placed))
            x += width + Self.gapD
        }
        self.departments = laid
        width = max(Self.ceoW, x - (laid.isEmpty ? 0 : Self.gapD))
        height = Self.y2 + (laid.flatMap(\.teams).map(\.height).max() ?? 0)
    }

    /// The connectors: CEO → each department, department → each of its teams (cubic, vertical tangents).
    var connectors: [(CGPoint, CGPoint)] {
        departments.flatMap { department in
            [(CGPoint(x: cx, y: Self.ceoH), CGPoint(x: department.cx, y: Self.y1))]
                + department.teams.map {
                    (CGPoint(x: department.cx, y: Self.y1 + Self.depH), CGPoint(x: $0.cx, y: Self.y2))
                }
        }
    }
}
