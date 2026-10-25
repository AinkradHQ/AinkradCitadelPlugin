import AinkradAppKit
import AppKit
import CitadelClient
import Foundation
import Observation

/// What the server must be asked again after an event: the event says *that* something changed, the fetch says
/// what it is now. Pushed, never polled.
enum Reload: Hashable, Sendable {
    case org, approvals, stuck, costs, requirements, sprint, accounts
    /// Agents' questions, from the open requirements' threads.
    case questions
    /// An issue's comments (an agent thread), once loaded.
    case comments(Int64)
    /// An issue read again even when known: its state or next actor moved.
    case issueFresh(Int64)
    /// An opened issue's pull requests (API minor 16).
    case pullRequests(Int64)
    /// The knowledge of each project whose list is loaded (API minor 16).
    case knowledge
    case agent(Int64)
    /// An agent's newest run (the one it is on now).
    case agentRun(Int64)
    case run(Int64)
    case issue(Int64)
    /// A requirement's thread and plan (screen 12), once opened.
    case thread(Int64)
    /// The artifacts list and the company's storage use (screen 13).
    case artifacts
    /// A project's profile and repos (screen 14).
    case profile(Int64)
    /// An opened project's work: issues, sprints, epics (the project page's tabs).
    case projectWork(Int64)
    /// Scoped settings (screens 10, 14, 15, 16).
    case settings
    /// Runners and their disk (screen 10).
    case runners
    /// The chain presets (API minor 18).
    case presets
    /// The roles (API minor 18).
    case roles
    /// The device keys (a pairing finished).
    case devices
}

/// The selected company as the screens read it, kept current by the event stream.
@MainActor
@Observable
final class CompanyModel {
    var companyID: Int64
    var agents: [Int64: AgentInfo] = [:]
    var departments: [DepartmentInfo] = []
    var runs: [Int64: RunInfo] = [:]
    var issues: [Int64: IssueInfo] = [:]
    var approvals: [ApprovalInfo] = []
    /// Decided approvals, newest first: the inbox's "Answered" section.
    var answeredApprovals: [ApprovalInfo] = []
    /// Agents' questions for you (open and answered), from the requirement threads.
    var questions: [QuestionInfo] = []
    /// Each loaded issue's comments, oldest first: the agent threads (screen 07).
    var comments: [Int64: [CommentInfo]] = [:]
    /// Each project's average velocity over its last sprints (points).
    var velocity: [Int64: Double] = [:]
    /// Each project's last sprints' completed points, oldest first (the approvals sprint KPI's sparkline).
    var velocitySeries: [Int64: [Int]] = [:]
    /// Each issue's worktree diff per repo, as its last run measured it (the merge approval's PR cards).
    var issueDiffs: [Int64: [RepoDiffInfo]] = [:]
    /// Runners online now, for the sidebar's "3/4".
    var runnersOnline = 0
    /// The Cost screen's period: its issues, its days (oldest first), this company's account use.
    var costTasks: [TaskCostInfo] = []
    var costDays: [DaySpend] = []
    /// The models with no price, most tokens first (API minor 18; empty on an older server).
    var unpriced: [UnpricedModelInfo] = []
    /// The company's named fallback chains by name (API minor 18; empty on an older server).
    var chainPresets: [ChainPresetInfo] = []
    /// The company's roles for the hire wizard and the Roles tab (API minor 18; empty on an older server).
    var roles: [RoleInfo] = []
    /// Each agent's server-side stats once read (API minor 18): the agent page, the Org peek.
    var agentStats: [Int64: Schemas.AgentStats] = [:]
    /// The company's notification preferences once read (API minor 18).
    var notifications: NotificationPrefs?
    var accountUse: [AccountUseInfo] = []
    /// The period the cost data is for; `nil` until the Cost screen first loads.
    var costPeriod: CostPeriod?
    /// The period's spend by agent and by department (`getSpendBreakdown`).
    var costByAgent: [ScopeSpend] = []
    var costByDepartment: [ScopeSpend] = []
    var stuck: [StuckInfo] = []
    var spend: SpendInfo?
    var budgets: [BudgetInfo] = []
    var requirements: [RequirementInfo] = []
    var sprint: SprintInfo?
    var projects: [ProjectInfo] = []
    /// Each issue's spend to date, as the run rail's "issue so far" needs it.
    var issueCosts: [Int64: IssueCost] = [:]
    /// Spend since local midnight, summed over the day's issues.
    var spendToday: IssueCost?
    /// Today's spend per hour since local midnight (Home's spend line).
    var hourSpend: [DaySpend] = []
    var accounts: [Int64: AccountInfo] = [:]
    var runners: [Int64: String] = [:]
    /// `run.token_cap`, `run.stall_after_secs`, `budget.warn_percent`, `breaker.loop_threshold`.
    var limits: [String: LimitSetting] = [:]
    /// Each loaded run's transcript, in `seq` order.
    var transcripts: [Int64: [TranscriptChunkInfo]] = [:]
    /// Each run's system lines (provider drops, fallbacks) seen on the stream.
    var notes: [Int64: [RunNote]] = [:]
    /// The repos each issue touches (decision #51), for the run's worktrees.
    var issueRepos: [Int64: [String]] = [:]
    /// The Runs screen's runs, newest first; `nil` until it first opens.
    var companyRuns: [RunInfo]?
    /// The agent page's runs, newest first.
    var agentRuns: [Int64: [RunInfo]] = [:]
    /// The newest tool call of each live run ("Bash cargo test -p citadel-server replay").
    var toolNow: [Int64: String] = [:]
    /// What blocks each opened issue, its project's sprints and issues (the thread's blocker and sprint menus).
    var blockers: [Int64: [IssueInfo]] = [:]
    var projectSprints: [Int64: [ProjectSprintInfo]] = [:]
    var projectIssues: [Int64: [IssueInfo]] = [:]
    /// The wakes seen on each issue, oldest first: whom they woke and why (API minor 14 says which agent).
    var wakes: [Int64: [WakeNote]] = [:]
    /// Each opened issue's pull requests (API minor 16), one per repo: state, checks, and a refused push or failed
    /// forge call; read again on each `pr.*` event.
    var issuePRs: [Int64: [IssuePRInfo]] = [:]
    /// Uploaded agent images (decision #61), drawn instead of the orb.
    var avatars: [Int64: NSImage] = [:]
    var isLoaded = false
    /// Screens 10 and 12–16 keep their own state, loaded when the screen opens and kept current by events.
    let requirementsPage = RequirementsPage()
    let artifactsPage = ArtifactsPage()
    let threadsPage = ThreadsPage()
    let runsPage = RunsPage()
    let projectsPage = ProjectsPage()
    let costPage = CostPage()
    let limitsPage = LimitsPage()
    let accountsPage = AccountsPage()
    let runnersPage = RunnersPage()
    let orgPage = OrgPage()

    init(companyID: Int64) {
        self.companyID = companyID
    }

    // MARK: - Reading

    var ceo: AgentInfo? { agents.values.first { $0.orgRole == "ceo" } }

    /// Running, claimed and queued runs, oldest first.
    var liveRuns: [RunInfo] {
        runs.values.filter(\.isLive).sorted { ($0.startedAt ?? $0.queuedAt) < ($1.startedAt ?? $1.queuedAt) }
    }

    /// The run an agent is on now, or its newest.
    func currentRun(of agent: Int64) -> RunInfo? {
        let mine = runs.values.filter { $0.agentID == agent }
        return mine.filter(\.isLive).max { $0.queuedAt < $1.queuedAt } ?? mine.max { $0.queuedAt < $1.queuedAt }
    }

    /// The pending permission escalation a run waits on.
    func waitingApproval(run: Int64) -> ApprovalInfo? {
        approvals.first { $0.kind == "permission_escalation" && $0.fields["run"] == String(run) }
    }

    var busyAgents: Int { agents.values.filter { [.working, .thinking, .loading].contains($0.figure) }.count }
    var pausedAgents: Int { agents.values.filter(\.isPaused).count }
    var idleAgents: Int { agents.count - busyAgents - pausedAgents }
    var needsYouCount: Int { approvals.count + stuck.count }

    func agent(_ id: Int64?) -> AgentInfo? { id.flatMap { agents[$0] } }
    func issue(_ id: Int64?) -> IssueInfo? { id.flatMap { issues[$0] } }

    /// A limit as it applies to a project: its own override, else the company's.
    func limit(_ key: String, project: Int64? = nil) -> LimitSetting? {
        project.flatMap { limits["project:\($0)|\(key)"] } ?? limits[key]
    }
    var stallAfter: TimeInterval? { limits["run.stall_after_secs"].map { TimeInterval($0.value) } }
    var runCap: Int64? { limits["run.token_cap"]?.value }
    var warnFraction: Double { Double(limits["budget.warn_percent"]?.value ?? 80) / 100 }

    // MARK: - The event stream

    /// Folds one event in: a transcript chunk is applied here; anything else names what to fetch again.
    func apply(_ event: Schemas.Event) -> Set<Reload> {
        switch event.payload {
        case .transcript(let t):
            return received(TranscriptChunkInfo(t.chunk), run: t.runId)
        case .wake(let wake):
            if let issue = wake.issueId {
                woke(
                    WakeNote(agentID: wake.agentId, source: wake.source.word, reason: wake.reason, at: event.at),
                    on: issue)
            }
            var reloads: Set<Reload> = [.agent(wake.agentId)]
            if let issue = wake.issueId, issues[issue] == nil { reloads.insert(.issue(issue)) }
            return reloads
        case .audit(let audit):
            return audited(
                action: audit.action, entity: audit.entityId, kind: audit.entityKind, run: audit.runId,
                details: flatFields(audit.details.value), at: event.at)
        }
    }

    /// Records a wake on an issue, once (the stream and your own post can both report it).
    func woke(_ note: WakeNote, on issue: Int64) {
        var notes = wakes[issue] ?? []
        if let last = notes.last, last.agentID == note.agentID, last.source == note.source,
            abs(last.at.timeIntervalSince(note.at)) < 10
        {
            return
        }
        notes.append(note)
        wakes[issue] = Array(notes.suffix(20))
    }

    func received(_ chunk: TranscriptChunkInfo, run: Int64) -> Set<Reload> {
        if var chunks = transcripts[run], !chunks.contains(where: { $0.seq == chunk.seq }) {
            chunks.append(chunk)
            chunks.sort { $0.seq < $1.seq }
            transcripts[run] = chunks
        }
        if chunk.kind == "tool_use" { toolNow[run] = ToolLine.line(chunk.fields) }
        guard var info = runs[run] else { return [.run(run)] }
        info.lastProgressAt = max(info.lastProgressAt ?? chunk.at, chunk.at)
        runs[run] = info
        // A turn's usage moves the meter; the run's totals are the server's to add up.
        return chunk.kind == "usage" ? [.run(run)] : []
    }

    func audited(
        action: String, entity: Int64?, kind: String?, run: Int64?, details: [String: String], at: Date
    ) -> Set<Reload> {
        let family = action.split(separator: ".").first.map(String.init) ?? action
        let runID = run ?? (family == "run" ? entity : nil)
        switch family {
        case "run":
            guard let runID else { return [] }
            if action == "run.provider_dropped" || action == "run.fallback" {
                notes[runID, default: []].append(RunNote(at: at, action: action, text: RunNote.text(action, details)))
            }
            return [.run(runID), .costs]
        case "approval": return [.approvals]
        case "question": return [.questions]
        case "agent": return entity.map { [.agent($0), .org] } ?? [.org]
        case "chain_preset": return [.presets, .org]
        case "role": return [.roles]
        case "device": return [.devices]
        case "budget": return [.costs]
        case "requirement":
            var reloads: Set<Reload> = [.requirements, .questions]
            if let entity { reloads.insert(.thread(entity)) }
            return reloads
        case "artifact": return [.artifacts]
        case "setting": return [.settings]
        case "runner": return [.runners]
        case "project": return entity.map { [.profile($0)] } ?? []
        case "sprint":
            return Set<Reload>([.sprint]).union(projectsPage.work.keys.map { Reload.projectWork($0) })
        case "pr":
            guard let entity, kind == nil || kind == "issue" else { return [] }
            var reloads: Set<Reload> = [.issueFresh(entity)]
            if comments[entity] != nil { reloads.insert(.comments(entity)) }
            if issuePRs[entity] != nil { reloads.insert(.pullRequests(entity)) }
            return reloads
        case "knowledge": return [.knowledge]
        case "account": return [.accounts, .settings]
        case "issue":
            var reloads: Set<Reload> = [.stuck]
            if let project = details["project_id"].flatMap(Int64.init), projectsPage.work[project] != nil {
                reloads.insert(.projectWork(project))
            }
            // Every issue event names its project (API minor 9): one in the active sprint's project moves Home's
            // sprint count.
            if let project = details["project_id"].flatMap(Int64.init), let sprint,
                projects.first(where: { $0.id == project })?.key == sprint.projectKey
            {
                reloads.insert(.sprint)
            }
            guard let entity, kind == nil || kind == "issue" else { return reloads }
            reloads.insert(issues[entity] == nil ? .issue(entity) : .issueFresh(entity))
            if action == "issue.commented", comments[entity] != nil { reloads.insert(.comments(entity)) }
            return reloads
        default: return []
        }
    }
}

/// One wake on an issue: whom, from what (`comment`, `assignment`, `blocker_closed`, …) and the server's reason.
struct WakeNote: Equatable, Sendable {
    var agentID: Int64
    var source: String
    var reason: String
    var at: Date
}

extension RunNote {
    /// "Provider dropped (overloaded) · resumed the same session after backoff".
    static func text(_ action: String, _ details: [String: String]) -> String {
        switch action {
        case "run.provider_dropped":
            let why = details["reason"].map { " (\($0))" } ?? ""
            let count = details["drops"].map { " · drop \($0)" } ?? ""
            return "Provider dropped\(why) · resumed the same session after backoff\(count)"
        case "run.fallback":
            let to = [details["harness"], details["model"]].compactMap { $0 }.joined(separator: " · ")
            return "Fell back to \(to.isEmpty ? "the next entry" : to) — \(details["reason"] ?? details["class"] ?? "")"
        default: return action
        }
    }
}

/// A tool call as one line: its name and its most telling argument.
enum ToolLine {
    static func argument(_ fields: [String: String]) -> String {
        for key in ["input.command", "input.file_path", "input.path", "input.url", "input.pattern", "input.query"] {
            if let value = fields[key], !value.isEmpty { return value }
        }
        return fields.filter { $0.key.hasPrefix("input.") }.sorted { $0.key < $1.key }.first?.value ?? ""
    }

    static func line(_ fields: [String: String]) -> String {
        let name = fields["name"] ?? fields["tool"] ?? "Tool"
        let argument = argument(fields)
        return argument.isEmpty ? name : "\(name) \(argument)"
    }
}
