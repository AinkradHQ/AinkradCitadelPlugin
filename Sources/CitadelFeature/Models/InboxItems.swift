import AinkradAppKit
import Foundation

/// The approvals inbox's filter chips (screen 06): All, then one per kind family.
enum ApprovalFilter: String, CaseIterable, Hashable {
    case all, sprint, merge, budget, hire, permission

    var title: String {
        switch self {
        case .all: "All"
        case .sprint: "Sprint"
        case .merge: "Merge"
        case .budget: "Budget"
        case .hire: "Hire"
        case .permission: "Permission"
        }
    }

    func matches(_ approval: ApprovalInfo) -> Bool {
        switch self {
        case .all: true
        case .sprint: ["sprint_commit", "plan_approval"].contains(approval.kind)
        case .merge: approval.kind == "pr_merge"
        case .budget: approval.kind == "budget_overrun"
        case .hire: approval.kind == "hire_agent"
        case .permission: approval.kind == "permission_escalation"
        }
    }
}

/// How one approval reads in the inbox list and its detail head: glyph, tone, the type label, a title and the
/// line under it.
struct ApprovalSummary: Equatable {
    let glyph: String
    let tone: AinkradChartTone
    /// "Sprint commit · CIT", "PR merge · 2 PRs".
    let typeLabel: String
    let title: String
    let subtitle: String
}

extension CompanyModel {
    /// The inbox: blocking a run first (permission, budget), then a sprint (commit, plan, merge), then hires;
    /// newest first within each.
    func inbox(_ filter: ApprovalFilter) -> [ApprovalInfo] {
        func rank(_ kind: String) -> Int {
            switch kind {
            case "permission_escalation", "budget_overrun": 0
            case "sprint_commit", "plan_approval", "pr_merge": 1
            default: 2
            }
        }
        return approvals.filter(filter.matches).sorted { (rank($0.kind), -$0.id) < (rank($1.kind), -$1.id) }
    }

    func summary(_ approval: ApprovalInfo) -> ApprovalSummary {
        let f = approval.fields
        let key = issue(approval.issueID)?.key ?? f["key"]
        let asker = agent(approval.agentID ?? approval.requestedBy)?.name
        switch approval.kind {
        case "sprint_commit":
            let issues = approval.lists["issues"] ?? []
            let project = issues.first?["key"].flatMap { $0.split(separator: "-").first.map(String.init) }
            let capacity = f["capacity"].map { " vs \($0) capacity" } ?? ""
            return ApprovalSummary(
                glyph: "◷", tone: .accentPrimary,
                typeLabel: ["Sprint commit", project].compactMap { $0 }.joined(separator: " · "),
                title: "Commit sprint \([project, f["name"]].compactMap { $0 }.joined(separator: " "))",
                subtitle: "\(f["points"] ?? "?") pts\(capacity)\(asker.map { " · \($0)" } ?? "")")
        case "plan_approval":
            return ApprovalSummary(
                glyph: "◷", tone: .accentPrimary, typeLabel: "Plan approval",
                title: "Approve the plan for \(f["key"] ?? "a requirement")",
                subtitle: [f["title"], f["points"].map { "\($0) pts" }].compactMap { $0 }.joined(separator: " · "))
        case "pr_merge":
            let prs = approval.lists["prs"] ?? []
            return ApprovalSummary(
                glyph: "⑂", tone: .success,
                typeLabel: "PR merge · \(prs.count == 1 ? "1 PR" : "\(max(prs.count, 1)) PRs")",
                title: f["summary"] ?? "Merge \(key ?? "the PRs")",
                subtitle: prs.map { "\($0["repo"] ?? "repo") #\($0["pr"] ?? "?")" }.joined(separator: " + "))
        case "budget_overrun":
            let spent = f["spent"].flatMap(Int64.init)
            let cap = f["token_cap"].flatMap(Int64.init).map { $0 + (f["raised"].flatMap(Int64.init) ?? 0) }
            let amounts = spent.map { s in "\(Fmt.tokens(s)) of \(cap.map(Fmt.tokens) ?? "?") tokens" }
            return ApprovalSummary(
                glyph: "$", tone: .warning, typeLabel: "Budget overrun · \(f["scope"] ?? "budget")",
                title: "\(key ?? asker ?? f["scope"] ?? "A") budget overrun",
                subtitle: [asker, amounts].compactMap { $0 }.joined(separator: " · "))
        case "hire_agent":
            return ApprovalSummary(
                glyph: "＋", tone: .accentViolet, typeLabel: "Hire",
                title: "Hire \(f["name"] ?? "an agent")\(f["role"].map { " · \($0)" } ?? "")",
                subtitle: [asker, f["harness"].map(AgentLook.harnessName), f["model"]].compactMap { $0 }.joined(
                    separator: " · "))
        case "permission_escalation":
            return ApprovalSummary(
                glyph: "⌁", tone: .warning, typeLabel: "Permission escalation · run #\(f["run"] ?? "?")",
                title: "\(asker ?? "An agent") wants to run \(f["tool"] ?? "a tool")",
                subtitle: [key, ToolLine.argument(f)].compactMap { $0 }.filter { !$0.isEmpty }.joined(separator: " · ")
            )
        default:
            return ApprovalSummary(
                glyph: "✓", tone: .accentPrimary, typeLabel: approval.kind.replacingOccurrences(of: "_", with: " "),
                title: f["summary"] ?? approval.kind.replacingOccurrences(of: "_", with: " "), subtitle: key ?? "")
        }
    }

    /// Who an approval's reply wakes: the agent that asked.
    func replyTarget(_ approval: ApprovalInfo) -> String {
        agent(approval.agentID ?? approval.requestedBy)?.name ?? "the agent"
    }

    /// Records a decision locally until the approval's event reloads the lists.
    func answer(_ approval: ApprovalInfo, approved: Bool, reply: String?) {
        approvals.removeAll { $0.id == approval.id }
        var decided = approval
        decided.status = approved ? "approved" : "rejected"
        decided.reply = reply
        answeredApprovals.removeAll { $0.id == approval.id }
        answeredApprovals.insert(decided, at: 0)
    }

    /// A comment you posted: appended to its thread, and the question it answered closed.
    func posted(_ comment: CommentInfo) {
        if !(comments[comment.issueID] ?? []).contains(where: { $0.id == comment.id }) {
            comments[comment.issueID, default: []].append(comment)
        }
        if let index = questions.lastIndex(where: { $0.issueID == comment.issueID && $0.isOpen }) {
            questions[index].state = "answered"
        }
    }
}

// MARK: - Agent threads

/// One agent on one issue: an agent thread (screen 07, decision #9 — a depth view, not an inbox).
struct ThreadKey: Hashable, Sendable {
    let agentID: Int64
    let issueID: Int64
}

/// A row of the threads list.
struct ThreadSummary: Identifiable, Equatable {
    var id: ThreadKey { key }
    let key: ThreadKey
    var requirementKey: String?
    /// "Quill: keep the founder story?", "run ended runner_lost".
    var lastLine: String
    /// An open question of the agent's on the issue.
    var waitingOnYou: Bool
    /// The newest run died (failed, lost, timed out) and nothing came after it.
    var died: Bool
    var at: Date
}

/// One line of a thread's conversation, in order.
enum ThreadLine: Identifiable, Equatable {
    case comment(CommentInfo)
    /// "▶ Run #422 · ended succeeded · $1.30".
    case run(RunInfo)
    /// The agent's open (or answered) question, with its quick replies.
    case question(QuestionInfo)

    var id: String {
        switch self {
        case .comment(let c): "c\(c.id)"
        case .run(let r): "r\(r.id)"
        case .question(let q): "q\(q.id)"
        }
    }
}

extension CompanyModel {
    /// Every run and every question we know of, as agent-on-issue threads: waiting on you first, then newest.
    func threads() -> [ThreadSummary] {
        var runsByKey: [ThreadKey: RunInfo] = [:]
        for run in Array(runs.values) + agentRuns.values.flatMap({ $0 }) {
            guard let issue = run.issueID else { continue }
            let key = ThreadKey(agentID: run.agentID, issueID: issue)
            if (runsByKey[key]?.queuedAt ?? .distantPast) < run.queuedAt { runsByKey[key] = run }
        }
        var keys = Set(runsByKey.keys)
        for question in questions { keys.insert(ThreadKey(agentID: question.agentID, issueID: question.issueID)) }
        let rows = keys.map { key -> ThreadSummary in
            let open = questions.filter { $0.isOpen && $0.agentID == key.agentID && $0.issueID == key.issueID }
                .max { $0.askedAt < $1.askedAt }
            let run = runsByKey[key]
            let name = agent(key.agentID)?.name ?? "Agent"
            let requirement = issue(key.issueID)?.requirementID.flatMap { id in requirements.first { $0.id == id } }
            let lastComment = comments[key.issueID]?.last
            let died = run.map { ["failed", "runner_lost", "timed_out"].contains($0.state) } ?? false
            let line: String =
                if let open { "\(name): \(open.text)" } else if let lastComment {
                    "\(lastComment.agentID.flatMap { agent($0)?.name } ?? "You"): \(lastComment.body)"
                } else if let run {
                    run.isLive ? "\(name) is working · run #\(run.id)" : "run ended \(run.endWord)"
                } else { "no messages yet" }
            return ThreadSummary(
                key: key, requirementKey: requirement?.key, lastLine: line, waitingOnYou: open != nil,
                died: died && open == nil && lastComment == nil,
                at: max(open?.askedAt ?? .distantPast, run?.endedAt ?? run?.startedAt ?? run?.queuedAt ?? .distantPast))
        }
        return rows.sorted {
            ($0.waitingOnYou ? 0 : 1, -$0.at.timeIntervalSince1970) < (
                $1.waitingOnYou ? 0 : 1, -$1.at.timeIntervalSince1970
            )
        }
    }

    /// A thread's conversation: comments in order, each run of the agent on the issue after the comment that
    /// woke it (by id order: a run's comments carry its id), and the open question last.
    func conversation(_ key: ThreadKey) -> [ThreadLine] {
        let issueRuns = (agentRuns[key.agentID] ?? [])
            .filter { $0.issueID == key.issueID }
            .sorted { $0.queuedAt < $1.queuedAt }
        var lines: [ThreadLine] = []
        var pending = issueRuns
        for comment in comments[key.issueID] ?? [] {
            // A run is placed before the first comment it wrote.
            if let runID = comment.runID, let index = pending.firstIndex(where: { $0.id == runID }) {
                lines += pending[...index].map(ThreadLine.run)
                pending.removeSubrange(...index)
            }
            lines.append(.comment(comment))
        }
        lines += pending.map(ThreadLine.run)
        lines += questions.filter { $0.agentID == key.agentID && $0.issueID == key.issueID }
            .sorted { $0.askedAt < $1.askedAt }
            .map(ThreadLine.question)
        return lines
    }

    /// The open question a message in this thread answers (decision #44's auto-target).
    func openQuestion(_ key: ThreadKey) -> QuestionInfo? {
        questions.filter { $0.isOpen && $0.issueID == key.issueID }.max { $0.askedAt < $1.askedAt }
    }

    /// "next actor: you", "next actor: Quill", "next actor: timer".
    func nextActorWord(_ issue: IssueInfo) -> String? {
        switch issue.nextActor {
        case .agent(let id): agent(id)?.name ?? "an agent"
        case .human: "you"
        case .timer: "a timer"
        case nil: nil
        }
    }
}

// MARK: - Sidebar

extension CompanyModel {
    /// A sidebar row's trailing count: plain for a size ("18"), a badge for what asks for you (amber approvals and
    /// accounts at a limit, red stuck). `nil` when there is nothing to count or the data isn't loaded.
    func navCount(_ screen: Screen) -> AinkradNavCount? {
        func plain(_ count: Int) -> AinkradNavCount? { count > 0 ? AinkradNavCount("\(count)") : nil }
        switch screen {
        case .requirements: return plain(requirements.filter { !["done", "cancelled"].contains($0.state) }.count)
        case .approvals: return approvals.isEmpty ? nil : AinkradNavCount("\(approvals.count)", tone: .warning)
        case .stuck: return stuck.isEmpty ? nil : AinkradNavCount("\(stuck.count)", tone: .danger)
        case .org: return plain(agents.count)
        case .runs: return plain(liveRuns.count)
        case .threads: return plain(questions.filter(\.isOpen).count)
        case .projects: return plain(projects.count)
        case .accounts:
            let hot = accounts.values.filter {
                $0.status == "limited" || ($0.windowUse ?? 0) * 100 >= Double($0.warnPercent ?? 80)
            }
            return hot.isEmpty ? nil : AinkradNavCount("\(hot.count)", tone: .warning)
        case .runners: return runners.isEmpty ? nil : AinkradNavCount("\(runnersOnline)/\(runners.count)")
        case .home, .artifacts, .cost: return nil
        }
    }
}
