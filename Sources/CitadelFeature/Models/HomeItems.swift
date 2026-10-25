import AinkradAppKit
import Foundation

/// How close a run is to its project's stall limit (screen 02 note 7, screen 05 liveness).
enum Liveness: Equatable {
    case fine
    /// Silent past 80 % of the limit: red, "about to stall".
    case nearStall
    case stalled
}

func liveness(silentFor seconds: TimeInterval, limit: TimeInterval?) -> Liveness {
    guard let limit, limit > 0 else { return .fine }
    if seconds >= limit { return .stalled }
    return seconds >= limit * 0.8 ? .nearStall : .fine
}

/// One row of "What needs you now": approvals, stuck issues, budgets near their line and runs about to stall, in
/// one list ordered blocking a run → blocking a sprint → everything else.
struct NeedsItem: Identifiable, Equatable {
    enum Tone: Equatable { case accent, warning, danger }

    enum Action: Equatable {
        /// Decided right here.
        case approve(ApprovalInfo, title: String)
        case openRun(Int64)
        case openScreen(Screen, title: String)
        /// "Review": the approval, open in the inbox.
        case review(Int64)
    }

    let id: String
    /// 0 blocks a run, 1 blocks a sprint, 2 everything else.
    let rank: Int
    let glyph: String
    let tone: Tone
    let title: String
    let subtitle: String
    let action: Action
}

extension CompanyModel {
    func needsItems(now: Date = Date()) -> [NeedsItem] {
        var items = approvals.map(needsItem)
        for (index, stuck) in stuck.enumerated() {
            let key = issue(stuck.issueID)?.key
            items.append(
                NeedsItem(
                    id: "stuck-\(index)", rank: 2, glyph: "⚑", tone: .danger,
                    title: [key, stuck.reason].compactMap { $0 }.joined(separator: " "), subtitle: stuck.action,
                    action: .openScreen(.stuck, title: "Why stuck")))
        }
        for budget in budgets where budget.fraction >= budget.warnFraction {
            items.append(
                NeedsItem(
                    id: "budget-\(budget.id)", rank: 2, glyph: "$", tone: .warning,
                    title: "\(budget.label) hit \(Int(budget.fraction * 100))% of its \(budget.period) budget",
                    subtitle:
                        "\(budget.spentWord) of \(budget.capWord)\(budget.isDollars ? "" : " tokens") · warn at \(budget.warnPercent)%",
                    action: .openScreen(.cost, title: "Cost")))
        }
        for run in liveRuns {
            let silent = now.timeIntervalSince(run.lastProgressAt ?? run.startedAt ?? run.queuedAt)
            guard run.state == "running", liveness(silentFor: silent, limit: stallAfter) != .fine else { continue }
            let who = agent(run.agentID)?.name ?? "A run"
            let on = issue(run.issueID).map { " on \($0.key)" } ?? ""
            let limit = Int((stallAfter ?? 0) / 60)
            let runner = run.runnerID.flatMap { runners[$0] }.map { " on \($0)" } ?? ""
            items.append(
                NeedsItem(
                    id: "stall-\(run.id)", rank: 0, glyph: "⏸", tone: .danger,
                    title: "\(who)'s run\(on) is about to stall",
                    subtitle:
                        "silent \(Int(silent / 60)) min · watchdog stops it at \(limit) and escalates · run #\(run.id)\(runner)",
                    action: .openRun(run.id)))
        }
        return items.enumerated().sorted { ($0.element.rank, $0.offset) < ($1.element.rank, $1.offset) }.map(\.element)
    }

    private func needsItem(_ approval: ApprovalInfo) -> NeedsItem {
        let f = approval.fields
        let key = issue(approval.issueID)?.key ?? f["key"]
        let who = agent(approval.agentID ?? approval.requestedBy)?.name
        let id = "approval-\(approval.id)"
        switch approval.kind {
        case "permission_escalation":
            return NeedsItem(
                id: id, rank: 0, glyph: "⌁", tone: .warning,
                title: "\(who ?? "An agent") asks to run \(f["tool"] ?? "a tool")",
                subtitle: [key, ToolLine.argument(f)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · "),
                action: .approve(approval, title: "Allow once"))
        case "budget_overrun":
            return NeedsItem(
                id: id, rank: 0, glyph: "$", tone: .warning,
                title: "\(who ?? key ?? "A budget") hit its cap", subtitle: "approve to raise it and resume",
                action: .review(approval.id))
        case "sprint_commit":
            let points = f["points"].map { " — \($0) pts" } ?? ""
            let capacity = f["capacity"].map { " vs \($0) capacity" } ?? ""
            return NeedsItem(
                id: id, rank: 1, glyph: "✓", tone: .accent, title: "Commit the sprint\(points)\(capacity)",
                subtitle: [who.map { "\($0) (PO)" }, key].compactMap { $0 }.joined(separator: " · "),
                action: .approve(approval, title: "Approve"))
        case "plan_approval":
            return NeedsItem(
                id: id, rank: 1, glyph: "✓", tone: .accent,
                title: "Approve the plan for \(f["key"] ?? "a requirement") — \(f["title"] ?? "")",
                subtitle: f["points"].map { "\($0) pts planned" } ?? "plan ready",
                action: .approve(approval, title: "Approve")
            )
        case "pr_merge":
            return NeedsItem(
                id: id, rank: 1, glyph: "⑂", tone: .accent, title: "Merge \(key ?? "the PRs")",
                subtitle: f["summary"] ?? "QA passed · ready to merge", action: .review(approval.id)
            )
        case "hire_agent":
            return NeedsItem(
                id: id, rank: 2, glyph: "＋", tone: .accent,
                title: "Hire \(f["name"] ?? "an agent")\(f["role"].map { " as \($0)" } ?? "")",
                subtitle: f["justification"] ?? "", action: .review(approval.id))
        default:
            return NeedsItem(
                id: id, rank: 2, glyph: "✓", tone: .accent,
                title: approval.kind.replacingOccurrences(of: "_", with: " "),
                subtitle: key ?? "", action: .review(approval.id))
        }
    }

    /// A live run card's state: waiting on you (amber), about to stall or stalled (red), else its age.
    func cardState(of run: RunInfo, now: Date = Date()) -> (word: String?, tone: NeedsItem.Tone?) {
        if waitingApproval(run: run.id) != nil { return ("waiting", .warning) }
        let silent = now.timeIntervalSince(run.lastProgressAt ?? run.startedAt ?? run.queuedAt)
        if run.state == "running", liveness(silentFor: silent, limit: stallAfter) != .fine {
            return ("stalled", .danger)
        }
        return (nil, nil)
    }
}

extension CompanyModel {
    /// An org row's second line — harness · model · what it is on now — and the colour a problem gives it
    /// (red runner lost, amber waiting / paused).
    func orgLine(_ agent: AgentInfo) -> (text: String, tone: NeedsItem.Tone?) {
        let base = "\(agent.harnessName) · \(agent.model)"
        if agent.isHirePending { return ("\(agent.harnessName) · not hired yet", nil) }
        if agent.isPaused { return ("\(base) · paused", .warning) }
        let run = currentRun(of: agent.id)
        switch agent.figure {
        case .listening: return ("\(base) · waiting on you", .warning)
        case .error: return ("\(base) · \(run?.endWord ?? "failed")", .danger)
        case .confused: return ("\(base) · stalled", .warning)
        case .working, .thinking, .loading: return ("\(base) · \(issue(run?.issueID)?.key ?? "working")", nil)
        case .sleepy: return ("\(base) · paused", .warning)
        default: return ("\(base) · idle", nil)
        }
    }
}
