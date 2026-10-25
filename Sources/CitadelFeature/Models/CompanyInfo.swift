import AinkradAppKit
import Foundation

// The screens' view of one company: plain values mapped from the generated client (`Mapping.swift`), so a view
// never reads a wire type and a test can build any state without JSON.

struct AgentInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    var role: String
    /// `ceo`, `cto` or `none`.
    var orgRole: String
    var harness: String
    var model: String
    var runnerTags: [String]
    /// `active`, `paused`, `pending_approval` or `terminated`.
    var status: String
    var figure: AinkradFigureState
    var paletteID: String
    /// The uploaded image's path on the server (decision #61), drawn instead of the orb.
    var avatarPath: String?
    var reportsTo: Int64?
    /// When it was proposed (`hired_at`; the approval seats it).
    var hiredAt: Date? = nil
    /// What the admin wrote, its effort, sandbox, standing instructions and rules (API minor 17); nil from an
    /// older server, which does not store them.
    var about: String? = nil
    var effort: String? = nil
    var sandbox: String? = nil
    var instructions: String? = nil
    var guidelines: [String]? = nil
    /// The chain preset it uses in place of its own fallbacks, and the wakes waiting for it (API minor 18).
    var chainPresetID: Int64? = nil
    var queuedWakes: Int64? = nil

    var isPaused: Bool { status == "paused" }
    var isHirePending: Bool { status == "pending_approval" }
    /// The figure's palette: the stored one, Muted while paused or retired.
    var palette: AinkradFigurePalette { AgentLook.palette(id: paletteID, status: status) }
    var figureHarness: AinkradFigureHarness? { AgentLook.harness(harness) }
    var harnessName: String { AgentLook.harnessName(harness) }
}

struct DepartmentInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    var teams: [TeamInfo]
    /// What it does, and the agent that heads it (API minor 17); nil from an older server.
    var about: String? = nil
    var headAgentID: Int64? = nil

    var agentIDs: [Int64] { teams.flatMap { $0.seats.map(\.agentID) } }
}

struct TeamInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    var seats: [SeatInfo]
}

struct SeatInfo: Equatable, Sendable {
    var agentID: Int64
    /// `product_owner`, `team_lead` or `member`.
    var teamRole: String
}

struct RunInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var agentID: Int64
    var issueID: Int64?
    /// `queued`, `claimed`, `running`, `succeeded`, `failed`, `cancelled`, `timed_out`, `runner_lost`.
    var state: String
    /// The run stopped on its token cap: a budget stop, not a lost run.
    var isCapHit: Bool { state == "failed" && terminalReason?.contains("cap") == true }
    /// The run died and left nothing to read: failed (unless it merely hit its cap), lost or timed out.
    var died: Bool { !isCapHit && ["failed", "runner_lost", "timed_out"].contains(state) }
    var harness: String
    var harnessVersion: String?
    var model: String?
    var accountID: Int64?
    var runnerID: Int64?
    var fallbackReason: String?
    var terminalReason: String?
    var inputTokens: Int64 = 0
    var outputTokens: Int64 = 0
    var cacheTokens: Int64 = 0
    var costMicros: Int64?
    var contextTokens: Int64?
    var queuedAt: Date
    var wokenAt: Date?
    var claimedAt: Date?
    var startedAt: Date?
    var harnessStartedAt: Date?
    var firstTokenAt: Date?
    var endedAt: Date?
    var lastProgressAt: Date?
    /// Each repo's diff against its base, as last measured, in the issue's repo order (`+38 −6`).
    var diffRepos: [RepoDiffInfo] = []
    /// Why its transcript is gone (`pruned` past `transcript.retention_secs`), and when it went.
    var transcriptGoneReason: String? = nil
    var transcriptPrunedAt: Date? = nil

    /// What a cap counts: every token, cache included.
    var tokens: Int64 { inputTokens + outputTokens + cacheTokens }
    var isLive: Bool { ["queued", "claimed", "running"].contains(state) }
    /// The run's end in the words of screen 04: `cap hit` is a failure the token cap caused.
    var endWord: String {
        if isCapHit { return "cap hit" }
        return state.replacingOccurrences(of: "_", with: " ")
    }
}

struct IssueInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var key: String
    var title: String
    var projectID: Int64
    var requirementID: Int64?
    /// `backlog`, `todo`, `in_progress`, `in_review`, `blocked`, `done`, `cancelled`.
    var state = ""
    /// Who moves it next (the engine invariant): an agent, you, or a timer.
    var nextActor: NextActorInfo?
    var points: Int?
    /// The planned or active sprint it is in.
    var sprintID: Int64? = nil
}

/// Who moves an issue next.
enum NextActorInfo: Equatable, Sendable {
    case agent(Int64)
    case human
    case timer(String)
}

struct ApprovalInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    /// `sprint_commit`, `pr_merge`, `budget_overrun`, `hire_agent`, `permission_escalation`, `plan_approval`.
    var kind: String
    var agentID: Int64?
    var issueID: Int64?
    var requestedBy: Int64
    var expiresAt: Date?
    /// When it was asked and answered (API minor 17); nil from an older server.
    var createdAt: Date? = nil
    var decidedAt: Date? = nil
    /// The payload's flat string and number fields (`name`, `key`, `title`, `tool`, `run`, `points`, …).
    var fields: [String: String]
    /// `pending`, `approved`, `rejected`, `expired`.
    var status = "pending"
    /// What the person replied with the decision.
    var reply: String?
    var sprintID: Int64?
    /// The payload's lists, each row flattened: `issues` (sprint commit), `prs` (PR merge), `tasks` (plan).
    var lists: [String: [[String: String]]] = [:]
}

/// An agent's question for the person (E15.11): open until answered in the issue or its requirement thread.
struct QuestionInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var agentID: Int64
    var issueID: Int64
    var issueKey: String
    var requirementID: Int64?
    var runID: Int64?
    var text: String
    /// Quick replies the agent offered.
    var options: [String]
    /// `open`, `answered`, `cancelled`.
    var state: String
    var askedAt: Date

    var isOpen: Bool { state == "open" }
}

/// One comment on an issue: the conversation of an agent thread (screen 07).
struct CommentInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var issueID: Int64
    /// The agent who wrote it; `nil` is a person (you).
    var agentID: Int64?
    var body: String
    /// The run an agent wrote it from.
    var runID: Int64?
}

struct StuckInfo: Equatable, Sendable {
    var kind: String
    var issueID: Int64?
    var agentID: Int64?
    var reason: String
    var action: String
    /// What the scheduler does about it by itself: the engine's recommendation (`rewake`, `reassign_to_lead`, …).
    var repair: String?
    /// The last automatic repair and when.
    var lastRepair: String?
    var lastRepairAt: Date?
    /// Since when it has not moved (`stuck_since`), for the card's age.
    var since: Date? = nil
    /// The run it is about, how long such work usually takes and what happened, as the server tells it (API
    /// minor 18); nil and empty from an older server.
    var runID: Int64? = nil
    var usualSecs: Int? = nil
    var trail: [TrailInfo] = []
}

/// One step of a stuck issue's evidence trail.
struct TrailInfo: Equatable, Sendable {
    var at: Date
    var what: String
}

struct RequirementInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var key: String
    var title: String
    /// `planning`, `plan_review`, `in_progress`, `done`, `cancelled`.
    var state: String
    var ownerAgentID: Int64?
    var points: Int = 0
    var donePoints: Int = 0
    var percentDone: Int = 0
    /// `YYYY-MM-DD`.
    var eta: String?
    /// When you asked for it (the list's age).
    var createdAt: Date? = nil
    /// When it was paused (API minor 18); `nil` while it runs.
    var pausedAt: Date? = nil
}

struct BudgetInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    /// What VoiceOver and the row read: "Company · day", "Kestrel · month".
    var label: String
    /// `agent:3`, `company:1`, `project:2`, `department:4`, `sprint:9`.
    var scope: String
    /// `day`, `week`, `month`, `total`.
    var period: String
    var periodKey: String
    var spent: Int64
    var cap: Int64
    var warnPercent: Int
    /// Tokens added by approved raises; `cap` includes them, the stored cap does not.
    var raised: Int64 = 0
    /// Runs stop at the cap, or it only warns.
    var hardStop = true
    /// Dollars beside the tokens (API minor 18), in millionths, the approved raises included; `nil` without one.
    var usdCap: Int64?
    /// Priced dollars spent in the period, in millionths.
    var usdSpent: Int64 = 0
    /// Dollars added by approved raises, in millionths; `usdCap` includes them, the stored cap does not.
    var raisedUsd: Int64 = 0

    var warnFraction: Double { Double(warnPercent) / 100 }
    /// How much of the cap is used: the larger of the token and the dollar share (the server stops at either).
    var fraction: Double {
        let tokens = cap > 0 ? Double(spent) / Double(cap) : 0
        let dollars = (usdCap ?? 0) > 0 ? Double(usdSpent) / Double(usdCap ?? 1) : 0
        return max(tokens, dollars)
    }
}

struct SpendInfo: Equatable, Sendable {
    var costMicros: Int64
    var runs: Int64
    var pricedRuns: Int64
    var unpricedRuns: Int64
    var unpricedTokens: Int64
    var subscriptionRuns: Int64
    var subscriptionTokens: Int64
    var pricedTokens: Int64
}

struct ProjectInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var key: String
    var name: String
    var teamID: Int64?
    /// `scrum` or `kanban`.
    var mode: String
    /// A symbol or emoji, and `#rrggbb` (API minor 18); `nil` falls back to the project's place in the list.
    var icon: String? = nil
    var color: String? = nil
    /// Where the uploaded logo is read from, when it has one (API minor 18).
    var logoURL: String? = nil
    /// Every team on it, the owner (`teamID`) first (API minor 18); empty from an older server.
    var teamIDs: [Int64] = []
    /// Runtime limits, stored and shown (API minor 18).
    var runnerTags: [String] = []
    var maxParallelRuns: Int? = nil
    var runTimeoutSecs: Int? = nil
    var worktreeKeepDays: Int? = nil

    /// The owner first, then the others; the owner alone from an older server.
    var allTeamIDs: [Int64] { teamIDs.isEmpty ? teamID.map { [$0] } ?? [] : teamIDs }
}

struct SprintInfo: Equatable, Sendable {
    var id: Int64
    var name: String
    var projectKey: String
    var startsOn: Date?
    var endsOn: Date?
    var committed: Int
    var completed: Int
}

struct AccountInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var label: String
    /// `metered` (API, dollars) or `subscription` (Claude Max, Codex Pro: tokens).
    var billing = "metered"
    /// `active`, `limited`, `unhealthy`, `disabled`.
    var status: String
    var statusReason: String?
    var statusUntil: Date?
    /// The fullest window: its share used (0…1+), its length and warn line.
    var windowUse: Double?
    var windowSecs: Int64?
    var warnPercent: Int64?
}

/// What one issue's runs used (`getTaskCosts`).
struct IssueCost: Equatable, Sendable {
    var issueID: Int64
    var tokens: Int64
    var costMicros: Int64
    var runs: Int64
    var unpricedRuns: Int64
}

/// A scoped setting as the run rail shows it: its value and where it was set (`company:1`; nil = the default).
struct LimitSetting: Equatable, Sendable {
    var value: Int64
    var source: String?
}

/// One chunk of a run's transcript (redacted by the server).
struct TranscriptChunkInfo: Equatable, Sendable {
    var seq: Int64
    var at: Date
    /// The harness event's `type`: `assistant_text`, `tool_use`, `approval_requested`, `usage`, `turn_ended`, ….
    var kind: String
    /// Its flat string fields, with `input.<key>` for a tool's input.
    var fields: [String: String]
}

/// A system line in a run (an audit event): a provider drop, a fallback.
struct RunNote: Equatable, Sendable {
    var at: Date
    var action: String
    var text: String
}
