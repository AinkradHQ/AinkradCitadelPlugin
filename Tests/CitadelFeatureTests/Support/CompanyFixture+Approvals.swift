import AinkradAppKit
import Foundation

@testable import CitadelFeature

/// The prototype's approvals and Why stuck data (`Designs/citadel/prototype/data.js` APPROVALS, ANSWERED, STUCK and
/// `stuck.js` STUCK_SLOW), in server shapes, so the sweep's shots sit beside the prototype's.
@MainActor
extension CompanyFixture {
    static func approvalsProto(_ model: CompanyModel) {
        let sprint: [(Int64, String, String, Int)] = [
            (62, "CIT-62", "APNs push for approvals", 8), (63, "CIT-63", "Device key revoke + list", 3),
            (64, "CIT-64", "OpenAPI spec diff in make test", 5), (65, "CIT-65", "Host / Origin checks", 3),
            (66, "CIT-66", "Rate limits on auth", 2), (67, "CIT-67", "Swift client generation", 3),
            (68, "CIT-68", "Replay soak test (10 min disconnect)", 3), (69, "CIT-69", "Docs: device keys", 2),
            (70, "CIT-70", "QA pass", 2),
        ]
        model.issues[42] = IssueInfo(
            id: 42, key: "CIT-42", title: "Event stream replay", projectID: 1, requirementID: 12)
        model.issues[61] = IssueInfo(
            id: 61, key: "CIT-61", title: "runner lease heartbeat", projectID: 1, requirementID: 12)
        echoHireStore(model)
        model.approvals = [
            ApprovalInfo(
                id: 23, kind: "permission_escalation", agentID: 4, issueID: 42, requestedBy: 4, expiresAt: nil,
                createdAt: now.addingTimeInterval(-60),
                fields: [
                    "run": "418", "request": "toolu_7", "tool": "Bash",
                    "input.command": "cargo add tokio-tungstenite@0.26 --features rustls",
                ]),
            ApprovalInfo(
                id: 24, kind: "budget_overrun", agentID: 15, issueID: 8, requestedBy: 15, expiresAt: nil,
                createdAt: now.addingTimeInterval(-180),
                fields: [
                    "scope": "issue", "scope_id": "8", "period": "total", "token_cap": "200000", "spent": "168000",
                    "raised": "0", "run": "427",
                ]),
            ApprovalInfo(
                id: 21, kind: "sprint_commit", agentID: nil, issueID: nil, requestedBy: 3, expiresAt: nil,
                createdAt: now.addingTimeInterval(-720),
                fields: [
                    "name": "S5", "points": "31", "capacity": "34", "starts_on": "2026-10-27", "ends_on": "2026-11-07",
                    "goal":
                        "Phone alerts and key hygiene. CIT-62 is the risk — it needs an Apple push key we don't have yet.",
                ],
                sprintID: 5,
                lists: ["issues": sprint.map { ["id": "\($0.0)", "key": $0.1, "title": $0.2, "points": "\($0.3)"] }]),
            ApprovalInfo(
                id: 22, kind: "pr_merge", agentID: nil, issueID: 61, requestedBy: 9, expiresAt: nil,
                createdAt: now.addingTimeInterval(-1500),
                fields: [
                    "summary": "Merge CIT-61 · 2 PRs · lease heartbeat",
                    "qa_notes":
                        "Killed the runner mid-run 5× — every run ended runner_lost within 30 s and was retried once. One nit left as a comment: heartbeat interval is hard-coded (now a setting, E15.17).",
                ],
                lists: [
                    "prs": [
                        ["repo": "citadel", "pr": "61", "url": "https://github.com/AinkradHQ/AinkradCitadel/pull/61"],
                        ["repo": "ainkrad-citadel-plugin", "pr": "14"],
                    ]
                ]),
            ApprovalInfo(
                id: 25, kind: "hire_agent", agentID: 18, issueID: nil, requestedBy: 14, expiresAt: nil,
                createdAt: now.addingTimeInterval(-7200),
                fields: [
                    "name": "Echo", "role": "social media", "org_role": "none", "harness": "opencode",
                    "model": "qwen3-coder", "runner_tags": "linux",
                    "justification":
                        "Quill is spending turns on threads and posts. A cheaper agent for social frees Quill for long-form.",
                ]),
        ]
        model.answeredApprovals = [
            ApprovalInfo(
                id: 17, kind: "pr_merge", agentID: nil, issueID: 49, requestedBy: 9, expiresAt: nil,
                createdAt: now.addingTimeInterval(-5400),
                fields: ["summary": "Merge PR #58 · wake queue"], status: "approved", reply: "merged")
        ]
        var run = CompanyFixture.run(418, agent: 4, issue: 42, minutes: 5, tokens: 40_000)
        run.state = "waiting"
        model.runs[418] = run
        model.velocity[1] = 29
        model.velocitySeries[1] = [27, 31, 29]
        func pr(_ repo: Int64, _ name: String, _ number: Int64) -> IssuePRInfo {
            IssuePRInfo(
                repoID: repo, repo: name, state: "open", title: "CIT-61 runner lease heartbeat", number: number,
                url: nil,
                head: "feat/cit-61-lease", base: "development", checks: "success", checksNote: nil, lastError: nil,
                pushHeld: nil, unpushedAt: nil)
        }
        model.issuePRs[61] = [pr(1, "citadel", 61), pr(2, "ainkrad-citadel-plugin", 14)]
        model.issueDiffs[61] = [
            RepoDiffInfo(repo: "citadel", files: 7, insertions: 214, deletions: 38),
            RepoDiffInfo(repo: "ainkrad-citadel-plugin", files: 3, insertions: 52, deletions: 9),
        ]
        model.projectsPage.policies[1] = PolicyInfo(mode: "sandboxed", allow: ["Bash:cargo test"], sandboxed: true)
    }

    /// Echo (the hire under review) as the store would hold it: its sandbox, attached skills and a month budget.
    static func echoHireStore(_ model: CompanyModel) {
        model.agents[18]?.sandbox = "read-only + web"
        model.orgPage.agentSkills[18] = [
            SkillInfo(
                id: 1, name: "brand-voice", version: 2, attachedTo: "agent", attachedID: 18, attachedRole: nil, bytes: 0
            ),
            SkillInfo(
                id: 2, name: "social-posting", version: 1, attachedTo: "agent", attachedID: 18, attachedRole: nil,
                bytes: 0),
        ]
        model.budgets.append(
            BudgetInfo(
                id: 18, label: "Echo · month", scope: "agent:18", period: "month", periodKey: "2026-10", spent: 0,
                cap: 5_000_000, warnPercent: 80))
    }

    static func stuckProto(_ model: CompanyModel) {
        runnersPage(model)
        for issue in [
            IssueInfo(id: 49, key: "CIT-49", title: "Retry budget for runner_lost", projectID: 1, requirementID: nil),
            IssueInfo(id: 9, key: "AMC-9", title: "Signed build on the Mac runner", projectID: 2, requirementID: nil),
            IssueInfo(id: 64, key: "CIT-64", title: "OpenAPI spec diff in make test", projectID: 1, requirementID: nil),
            IssueInfo(id: 58, key: "CIT-58", title: "Escalation chain skips CEO", projectID: 1, requirementID: nil),
            IssueInfo(id: 60, key: "CIT-60", title: "Push for blocked work", projectID: 1, requirementID: nil),
        ] { model.issues[issue.id] = issue }
        model.runs[430] = CompanyFixture.run(430, agent: 8, issue: 64, minutes: 24, tokens: 90_000, silentFor: 540)
        model.stuck = [
            StuckInfo(
                kind: "run_queued_no_lease", issueID: 49, agentID: 8, reason: "runner lost, retries used up",
                action:
                    "Rook's run #422 ended runner_lost when hetzner-2 stopped heart-beating; the retry also landed on hetzner-2 and was lost. No healthy runner had a free slot since",
                repair: "requeue", lastRepair: "requeue", lastRepairAt: now.addingTimeInterval(-3_600),
                since: now.addingTimeInterval(-7_200)),
            StuckInfo(
                kind: "wake_no_runner", issueID: 9, agentID: 11, reason: "needs a macos runner; the only one is asleep",
                action: "ahmed-mbp went to sleep at 01:40. The issue is queued and Pike is idle waiting for it",
                repair: "notify", lastRepair: nil, lastRepairAt: nil, since: now.addingTimeInterval(-25_200)),
            StuckInfo(
                kind: "issue_idle", issueID: 64, agentID: 8, reason: "run about to stall",
                action:
                    "Rook has made no tool call, file change or message on run #430. At 10 minutes the watchdog stops it as stalled and escalates to Toma",
                repair: "rewake", lastRepair: nil, lastRepairAt: nil, since: now.addingTimeInterval(-540)),
            StuckInfo(
                kind: "reviewer_inactive", issueID: 58, agentID: 9, reason: "reviewer queue",
                action:
                    "The QA step is assigned to Sable, but Sable's queue has 4 items ahead. Usual review time on this project: 1h 20m",
                repair: "reassign_to_lead", lastRepair: nil, lastRepairAt: nil, since: now.addingTimeInterval(-18_000)),
            StuckInfo(
                kind: "in_progress_idle", issueID: 60, agentID: 5, reason: "blocked by CIT-62",
                action: "(APNs push), which needs an Apple push key from you. It wakes on its own when CIT-62 closes",
                repair: "rewake", lastRepair: "rewake", lastRepairAt: now.addingTimeInterval(-7_200),
                since: now.addingTimeInterval(-86_400)),
        ]
    }
}
