import Foundation
import Observation

/// The Runs screen's state tabs (prototype `RUNS_FILTERS`).
enum RunsTab: String, CaseIterable, Hashable {
    case all, running, waiting, failed, succeeded

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    var icon: String {
        switch self {
        case .all: "person.2"
        case .running: "play"
        case .waiting: "clock"
        case .failed: "xmark.circle"
        case .succeeded: "checkmark.circle"
        }
    }
}

/// The Runs screen's filters and its peek drawer, kept while the screen is away.
@MainActor
@Observable
final class RunsPage {
    var tab: RunsTab = .all
    var agentID: Int64?
    var projectID: Int64?
    /// The run the peek drawer shows.
    var peekID: Int64?
    /// The picker whose menu is open: `agent` or `project`.
    var openPicker: String?

    var isFiltered: Bool { tab != .all || agentID != nil || projectID != nil }

    func clear() {
        tab = .all
        agentID = nil
        projectID = nil
    }
}

/// A run in the prototype's words (`RUNS_STATE`, `RS_TONE`): its state key, word, outcome glyph, tone and tab.
struct RunLook: Equatable {
    enum Tone: Equatable { case run, ok, warn, err, idle }

    /// `running`, `queued`, `paused`, `waiting`, `stalled`, `succeeded`, `runner_lost`, `cap_hit`, `cancelled`,
    /// `failed`, `timed_out`, `stopped`.
    let key: String

    var word: String {
        switch key {
        case "waiting": "waiting on you"
        case "stalled": "stalling"
        default: key.replacingOccurrences(of: "_", with: " ")
        }
    }

    var glyph: String {
        switch key {
        case "succeeded": "✓"
        case "runner_lost": "⚑"
        case "failed", "timed_out": "✕"
        case "stopped", "paused": "⏸"
        case "cap_hit": "$"
        case "cancelled": "■"
        case "running", "queued": "▶"
        case "waiting": "?"
        case "stalled": "!"
        default: "·"
        }
    }

    var tone: Tone {
        switch key {
        case "succeeded": .ok
        case "runner_lost", "failed", "timed_out", "stopped", "stalled": .err
        case "cap_hit", "paused", "waiting": .warn
        case "running", "queued": .run
        default: .idle
        }
    }

    var tab: RunsTab {
        switch key {
        case "running", "queued", "paused": .running
        case "waiting": .waiting
        case "succeeded": .succeeded
        default: .failed
        }
    }

    var isLive: Bool { ["running", "queued", "paused", "waiting", "stalled"].contains(key) }

    /// The peek drawer's "why" line, for the states that need one (`runs.js` `why`).
    func why(_ run: RunInfo) -> String? {
        switch key {
        case "runner_lost":
            "The runner stopped heartbeating · lease expired after 30 s. Retry budget used — the issue waits in Why stuck."
        case "cap_hit": "Stopped at the token cap. Raise the cap to resume."
        case "cancelled": "Stopped by you. The worktree and branch are kept."
        case "waiting": "Waiting on your decision · the watchdog is paused."
        case "stalled": "No tool call for a while — the watchdog stops it at its stall limit and escalates."
        case "stopped": "No activity past the stall limit — stopped and escalated to the lead."
        case "failed", "timed_out":
            run.terminalReason.flatMap { $0.isEmpty ? nil : $0 } ?? "The run ended with an error."
        default: nil
        }
    }

    /// `18m`, `1h40m`, `42s` (`runs.js` `dur`).
    static func span(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        let m = s % 3600 / 60
        return m == 0 ? "\(s / 3600)h" : "\(s / 3600)h\(m)m"
    }
}

/// A run's cost as the screens word it: never `$0` — `subscription` or `unpriced` instead.
enum RunCost: Equatable {
    case priced(Int64)
    case subscription
    case unpriced

    var word: String {
        switch self {
        case .priced(let micros): Fmt.dollars(micros: micros)
        case .subscription: "subscription"
        case .unpriced: "unpriced"
        }
    }
}

extension CompanyModel {
    func look(_ run: RunInfo, now: Date = Date()) -> RunLook {
        if run.isLive {
            if waitingApproval(run: run.id) != nil { return RunLook(key: "waiting") }
            if cardState(of: run, now: now).tone == .danger { return RunLook(key: "stalled") }
            if agent(run.agentID)?.isPaused == true { return RunLook(key: "paused") }
            return RunLook(key: run.state == "running" ? "running" : "queued")
        }
        let reason = run.terminalReason?.lowercased() ?? ""
        switch run.state {
        case "failed" where reason.contains("cap"): return RunLook(key: "cap_hit")
        case "failed" where reason.contains("stall") || reason.contains("watchdog"): return RunLook(key: "stopped")
        case "succeeded", "runner_lost", "cancelled", "timed_out", "failed": return RunLook(key: run.state)
        default: return RunLook(key: run.state)
        }
    }

    /// The account billed by subscription words a run without a price as `subscription`.
    func cost(_ run: RunInfo) -> RunCost {
        let subscription = run.accountID.flatMap { accounts[$0] }?.billing == "subscription"
        if let micros = run.costMicros, micros > 0 || !subscription { return .priced(micros) }
        return subscription ? .subscription : .unpriced
    }

    func elapsed(_ run: RunInfo, now: Date = Date()) -> TimeInterval {
        (run.endedAt ?? now).timeIntervalSince(run.startedAt ?? run.queuedAt)
    }

    /// The token cap a run burns toward: its agent's, its project's, else the company's.
    func cap(of run: RunInfo) -> Int64? {
        limits["run.token_cap.agent.\(run.agentID)"]?.value
            ?? limit("run.token_cap", project: issue(run.issueID)?.projectID)?.value
    }

    /// Every run the Runs screen knows: live ones first (as the stream keeps them), then the ended page.
    var knownRuns: [RunInfo] {
        let live = liveRuns
        let ids = Set(live.map(\.id))
        let ended = (companyRuns ?? []).filter { !ids.contains($0.id) && runs[$0.id]?.isLive != true && !$0.isLive }
        return live + ended
    }

    /// The runs the filters keep (state tab, agent, project).
    func runsMatching(tab: RunsTab, agent: Int64?, project: Int64?, now: Date = Date()) -> [RunInfo] {
        knownRuns.filter {
            (tab == .all || look($0, now: now).tab == tab) && (agent == nil || $0.agentID == agent)
                && (project == nil || issue($0.issueID)?.projectID == project)
        }
    }

    func runsCount(_ tab: RunsTab, now: Date = Date()) -> Int {
        tab == .all ? knownRuns.count : knownRuns.filter { look($0, now: now).tab == tab }.count
    }
}

/// The history's day groups: "Today", "Yesterday", a weekday within the week, then the date.
enum RunDay {
    static func title(_ date: Date, now: Date = Date(), calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return "Today" }
        if let yesterday = calendar.date(byAdding: .day, value: -1, to: now),
            calendar.isDate(date, inSameDayAs: yesterday)
        {
            return "Yesterday"
        }
        let days = calendar.dateComponents([.day], from: date, to: now).day ?? 0
        return days < 7
            ? date.formatted(.dateTime.weekday(.wide)) : date.formatted(.dateTime.month(.abbreviated).day())
    }

    /// Ended runs grouped by the day they ended, newest first.
    static func groups(_ runs: [RunInfo], now: Date = Date()) -> [(title: String, runs: [RunInfo])] {
        var groups: [(title: String, runs: [RunInfo])] = []
        for run in runs.sorted(by: { ($0.endedAt ?? $0.queuedAt) > ($1.endedAt ?? $1.queuedAt) }) {
            let title = title(run.endedAt ?? run.queuedAt, now: now)
            if groups.last?.title == title {
                groups[groups.count - 1].runs.append(run)
            } else {
                groups.append((title, [run]))
            }
        }
        return groups
    }
}

/// A tool by name as the transcript and the peek's steps draw it (`RS_TOOL`): an SF symbol and a hue.
enum ToolLook {
    enum Hue: Equatable { case blue, violet, green, cyan, pink, slate }

    static func hue(_ name: String) -> Hue {
        switch name {
        case "Read", "Grep", "Glob": .blue
        case "Edit", "MultiEdit": .violet
        case "Write": .green
        case "Bash": .cyan
        case "WebFetch", "WebSearch": .pink
        default: .slate
        }
    }

    static func icon(_ name: String) -> String {
        switch hue(name) {
        case .blue: "eye"
        case .violet: "pencil"
        case .green: "plus"
        case .cyan: "chevron.right"
        case .pink: "globe"
        case .slate: "circle"
        }
    }
}
