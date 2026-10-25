import AinkradAppKit
import Foundation

@testable import CitadelFeature

/// Screens 06 and 07 of the mockups' company: the approvals inbox and the agent threads.
@MainActor
extension CompanyFixture {
    static func inboxPage(_ model: CompanyModel) {
        let sprintIssues: [[String: String]] = [
            ["key": "CIT-62", "title": "APNs push for approvals", "points": "8"],
            ["key": "CIT-63", "title": "Device key revoke + list", "points": "3"],
            ["key": "CIT-64", "title": "OpenAPI spec diff in make test", "points": "5"],
            ["key": "CIT-65", "title": "Host / Origin checks", "points": "3"],
            ["key": "CIT-66", "title": "Rate limits on auth", "points": "2"],
            ["key": "CIT-67", "title": "Swift client generation", "points": "5"],
            ["key": "CIT-68", "title": "Replay soak test", "points": "3"],
        ]
        model.approvals = [
            ApprovalInfo(
                id: 21, kind: "sprint_commit", agentID: nil, issueID: nil, requestedBy: 3, expiresAt: nil,
                createdAt: now.addingTimeInterval(-720),
                fields: ["name": "S5", "points": "31", "capacity": "34", "goal": "Phone alerts and key hygiene"],
                sprintID: 5, lists: ["issues": sprintIssues]),
            ApprovalInfo(
                id: 22, kind: "pr_merge", agentID: nil, issueID: 61, requestedBy: 9, expiresAt: nil,
                createdAt: now.addingTimeInterval(-1500),
                fields: [
                    "summary": "Merge 2 PRs (citadel #61, ainkrad-citadel-plugin #14): runner lease heartbeat",
                    "qa_notes":
                        "Killed the runner mid-run 5× — every run ended runner_lost within 30 s and was retried once.",
                ],
                lists: [
                    "prs": [
                        ["repo": "citadel", "pr": "61", "url": "https://github.com/AinkradHQ/AinkradCitadel/pull/61"],
                        ["repo": "ainkrad-citadel-plugin", "pr": "14"],
                    ]
                ]),
            ApprovalInfo(
                id: 23, kind: "permission_escalation", agentID: 4, issueID: 42, requestedBy: 4, expiresAt: nil,
                createdAt: now.addingTimeInterval(-60),
                fields: [
                    "run": "418", "request": "r7", "tool": "Bash",
                    "input.command": "cargo add tokio-tungstenite@0.26 --features rustls",
                ]),
            ApprovalInfo(
                id: 24, kind: "budget_overrun", agentID: nil, issueID: 8, requestedBy: 15, expiresAt: nil,
                createdAt: now.addingTimeInterval(-180),
                fields: [
                    "scope": "agent", "scope_id": "15", "token_cap": "200000", "spent": "200400", "raised": "0",
                    "summary": "agent 15 day budget exhausted: 200400 of 200000 tokens spent",
                ]),
            ApprovalInfo(
                id: 25, kind: "hire_agent", agentID: 18, issueID: nil, requestedBy: 14, expiresAt: nil,
                createdAt: now.addingTimeInterval(-7200),
                fields: [
                    "name": "Echo", "role": "social", "org_role": "none", "harness": "opencode",
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
        model.velocity[1] = 29
        echoHireStore(model)
    }

    static func threadsPage(_ model: CompanyModel) {
        model.questions = [
            QuestionInfo(
                id: 3, agentID: 15, issueID: 8, issueKey: "MKT-8", requirementID: 10, runID: 419,
                text:
                    "Rewrote the intro with Nadia's tone notes. One call I need from you before the last pass: keep the founder story (adds ~180 words, over the 900 limit) or cut it?",
                options: ["Keep it, raise the limit to 1,100", "Cut it", "Move it to a separate post"],
                state: "open", askedAt: now.addingTimeInterval(-30))
        ]
        model.comments[8] = [
            CommentInfo(
                id: 1, issueID: 8, agentID: nil,
                body:
                    "Draft the launch post for Ainkrad 1.0. Lead with the \"OS, not web app\" idea, under 900 words. Quote Grimoire and Forge users if we have any.",
                runID: nil),
            CommentInfo(
                id: 2, issueID: 8, agentID: 15,
                body:
                    "First draft is up — 860 words. I didn't find user quotes in the knowledge base, so I left two marked placeholders instead of inventing them.",
                runID: 405),
        ]
        var first = ended(405, issue: 8, state: "succeeded", daysAgo: 0.2, minutes: 22, cost: 1_100_000)
        first.agentID = 15
        var capHit = ended(
            419, issue: 8, state: "failed", daysAgo: 0.05, minutes: 26, cost: 3_100_000,
            reason: "token cap 50,000 reached")
        capHit.agentID = 15
        var live = run(427, agent: 15, issue: 8, minutes: 14.4, tokens: 42_000, silentFor: 12 * 60)
        live.costMicros = 4_200_000
        live.state = "running"
        model.runs[419] = nil
        model.runs[427] = live
        model.toolNow[427] = "asks to fetch ainkrad.io/press"
        model.agentRuns[15] = [live, capHit, first]
        var lost = ended(
            409, issue: 49, state: "runner_lost", daysAgo: 0.1, minutes: 3, cost: 200_000, reason: "runner_lost")
        lost.agentID = 8
        model.runs[409] = lost
        model.issues[8]?.state = "in_progress"
        model.issues[8]?.nextActor = .human
        model.issueCosts[8] = IssueCost(issueID: 8, tokens: 121_000, costMicros: 4_200_000, runs: 3, unpricedRuns: 0)
    }
}
