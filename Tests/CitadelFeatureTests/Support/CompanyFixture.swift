import AinkradAppKit
import Foundation

@testable import CitadelFeature

/// The mockups' company (Designs/citadel 02–05) as plain values, for the screenshot sweep and view tests.
@MainActor
enum CompanyFixture {
    static let now = Date()

    static func agent(
        _ id: Int64, _ name: String, role: String, harness: String = "claude", model: String = "sonnet-5",
        figure: AinkradFigureState = .idle, palette: String, status: String = "active", orgRole: String = "none",
        reportsTo: Int64? = nil, tags: [String] = ["linux"]
    ) -> AgentInfo {
        AgentInfo(
            id: id, name: name, role: role, orgRole: orgRole, harness: harness, model: model, runnerTags: tags,
            status: status, figure: figure, paletteID: palette, avatarPath: nil, reportsTo: reportsTo)
    }

    static func run(
        _ id: Int64, agent: Int64, issue: Int64, minutes: Double, tokens: Int64, silentFor: Double = 5,
        harness: String = "claude", model: String = "sonnet-5"
    ) -> RunInfo {
        let started = now.addingTimeInterval(-minutes * 60)
        return RunInfo(
            id: id, agentID: agent, issueID: issue, state: "running", harness: harness, harnessVersion: nil,
            model: model, accountID: 2, runnerID: 1, fallbackReason: nil, terminalReason: nil,
            inputTokens: tokens * 3 / 4, outputTokens: tokens / 4, cacheTokens: 0, costMicros: 940_000,
            contextTokens: 11_200, queuedAt: started.addingTimeInterval(-9), wokenAt: started.addingTimeInterval(-9),
            claimedAt: started.addingTimeInterval(-8.6), startedAt: started.addingTimeInterval(-7.5),
            harnessStartedAt: started.addingTimeInterval(-1.6), firstTokenAt: started,
            endedAt: nil, lastProgressAt: now.addingTimeInterval(-silentFor))
    }

    static func model() -> CompanyModel {
        let model = CompanyModel(companyID: 1)
        let agents = [
            agent(1, "Aldric", role: "CEO", model: "opus-5.5", figure: .idle, palette: "ultraviolet", orgRole: "ceo"),
            agent(
                2, "Vesper", role: "CTO", model: "opus-5.5", figure: .working, palette: "dusk", orgRole: "cto",
                reportsTo: 1),
            agent(3, "Mira", role: "PO", figure: .thinking, palette: "orchid", reportsTo: 2),
            agent(
                4, "Kestrel", role: "dev", harness: "codex", model: "gpt-5.5", figure: .working, palette: "neon-tide",
                reportsTo: 2),
            agent(5, "Wren", role: "dev", figure: .idle, palette: "jade", reportsTo: 2),
            agent(
                6, "Finch", role: "dev", harness: "opencode", model: "qwen3", figure: .idle, palette: "cobalt",
                reportsTo: 2),
            agent(7, "Toma", role: "Lead", model: "opus-5.5", figure: .idle, palette: "copper", reportsTo: 2),
            agent(8, "Rook", role: "dev", figure: .working, palette: "coral", reportsTo: 2),
            agent(9, "Sable", role: "QA", figure: .working, palette: "steel", reportsTo: 2),
            agent(
                10, "Ibis", role: "dev", harness: "agy", model: "gemini-3", figure: .idle, palette: "lagoon",
                reportsTo: 2),
            agent(
                11, "Pike", role: "dev", model: "opus-5.5", figure: .working, palette: "ember", reportsTo: 2,
                tags: ["macos"]),
            agent(12, "Juno", role: "Lead", model: "opus-5.5", figure: .idle, palette: "glacier", reportsTo: 2),
            agent(
                13, "Lark", role: "QA", harness: "codex", model: "gpt-5.5", figure: .sleepy, palette: "aurora",
                status: "paused", reportsTo: 2),
            agent(14, "Nadia", role: "PO", figure: .idle, palette: "sakura", reportsTo: 1),
            agent(15, "Quill", role: "writer", figure: .listening, palette: "citrine", reportsTo: 14),
            agent(
                16, "Hue", role: "designer", harness: "agy", model: "gemini-3", figure: .idle, palette: "abyss",
                reportsTo: 14),
            agent(
                17, "Marr", role: "analyst", harness: "opencode", model: "qwen3", figure: .idle,
                palette: "lime-circuit", reportsTo: 14),
            agent(
                18, "Echo", role: "social", harness: "opencode", model: "qwen3", figure: .rest, palette: "aurora",
                status: "pending_approval", reportsTo: 14),
        ]
        model.agents = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
        func seats(_ ids: [(Int64, String)]) -> [SeatInfo] { ids.map { SeatInfo(agentID: $0.0, teamRole: $0.1) } }
        model.departments = [
            DepartmentInfo(
                id: 1, name: "Engineering",
                teams: [
                    TeamInfo(
                        id: 1, name: "Citadel Core",
                        seats: seats([
                            (3, "product_owner"), (7, "team_lead"), (4, "member"), (8, "member"), (5, "member"),
                            (9, "member"), (6, "member"),
                        ])),
                    TeamInfo(
                        id: 2, name: "Mac client",
                        seats: seats([(10, "member"), (12, "team_lead"), (11, "member"), (13, "member")])),
                ]),
            DepartmentInfo(
                id: 2, name: "Marketing",
                teams: [
                    TeamInfo(
                        id: 3, name: "Launch",
                        seats: seats([
                            (14, "product_owner"), (15, "member"), (16, "member"), (17, "member"), (18, "member"),
                        ]))
                ]),
        ]
        model.projects = [
            ProjectInfo(id: 1, key: "CIT", name: "Citadel", teamID: 1, mode: "scrum"),
            ProjectInfo(id: 2, key: "AMC", name: "Ainkrad Mac", teamID: 2, mode: "kanban"),
            ProjectInfo(id: 3, key: "MKT", name: "Launch", teamID: 3, mode: "scrum"),
        ]
        let issues = [
            IssueInfo(
                id: 42, key: "CIT-42", title: "Event stream replay from last-seen id", projectID: 1, requirementID: 8),
            IssueInfo(id: 12, key: "AMC-12", title: "Citadel plugin scaffold", projectID: 2, requirementID: nil),
            IssueInfo(id: 8, key: "MKT-8", title: "Launch blog post draft", projectID: 3, requirementID: 10),
            IssueInfo(id: 64, key: "CIT-64", title: "OpenAPI spec diff", projectID: 1, requirementID: nil),
            IssueInfo(id: 61, key: "CIT-61", title: "Runner lease heartbeat", projectID: 1, requirementID: nil),
            IssueInfo(id: 49, key: "CIT-49", title: "Wake queue coalescing", projectID: 1, requirementID: nil),
            IssueInfo(id: 9, key: "AMC-9", title: "Notarize the plugin", projectID: 2, requirementID: nil),
            IssueInfo(id: 57, key: "CIT-57", title: "Approval expiry sweep", projectID: 1, requirementID: nil),
        ]
        model.issues = Dictionary(uniqueKeysWithValues: issues.map { ($0.id, $0) })
        let runs = [
            run(418, agent: 4, issue: 42, minutes: 4.2, tokens: 82_400, harness: "codex", model: "gpt-5.5"),
            run(421, agent: 11, issue: 12, minutes: 1, tokens: 18_000, model: "opus-5.5"),
            run(419, agent: 15, issue: 8, minutes: 6, tokens: 168_000),
            run(430, agent: 8, issue: 64, minutes: 14, tokens: 66_000, silentFor: 9 * 60),
        ]
        model.runs = Dictionary(uniqueKeysWithValues: runs.map { ($0.id, $0) })
        model.toolNow = [
            418: "Bash cargo test -p citadel-server replay", 421: "Edit Sources/Citadel/CitadelApp.swift",
        ]
        model.approvals = [
            ApprovalInfo(
                id: 1, kind: "sprint_commit", agentID: nil, issueID: nil, requestedBy: 3, expiresAt: nil,
                fields: ["points": "31", "capacity": "34"]),
            ApprovalInfo(
                id: 2, kind: "pr_merge", agentID: nil, issueID: 61, requestedBy: 9, expiresAt: nil,
                fields: ["summary": "Sable verified · citadel #61 + plugin #14 · +266 −47"]),
            ApprovalInfo(
                id: 3, kind: "permission_escalation", agentID: 15, issueID: 8, requestedBy: 15, expiresAt: nil,
                fields: ["run": "419", "tool": "WebFetch", "input.url": "ainkrad.io/press"]),
        ]
        model.stuck = [
            StuckInfo(
                kind: "no_next_actor", issueID: 49, agentID: 8, reason: "has no next actor for 2h",
                action: "Rook's run ended runner_lost on hetzner-2 · retry budget used"),
            StuckInfo(
                kind: "wake_no_runner", issueID: 9, agentID: 11, reason: "waiting on the Mac runner",
                action: "needs tag macos · ahmed-mbp asleep since 01:40"),
        ]
        model.spend = SpendInfo(
            costMicros: 18_400_000, runs: 41, pricedRuns: 37, unpricedRuns: 2, unpricedTokens: 240_000,
            subscriptionRuns: 2, subscriptionTokens: 1_200_000, pricedTokens: 2_600_000)
        model.budgets = [
            BudgetInfo(
                id: 1, label: "MKT-8 · Quill", scope: "agent:15", period: "day", periodKey: "2026-10-23",
                spent: 168_000, cap: 200_000, warnPercent: 80),
            BudgetInfo(
                id: 2, label: "Marketing", scope: "department:2", period: "month", periodKey: "2026-10",
                spent: 710_000, cap: 1_000_000, warnPercent: 80),
            BudgetInfo(
                id: 3, label: "Kestrel", scope: "agent:4", period: "month", periodKey: "2026-10", spent: 3_120_000,
                cap: 8_000_000, warnPercent: 80),
        ]
        model.requirements = [
            RequirementInfo(
                id: 12, key: "R-12", title: "Phone alerts when I'm needed", state: "in_progress", ownerAgentID: 3,
                points: 31, donePoints: 5, percentDone: 16, eta: "2026-10-27"),
            RequirementInfo(
                id: 10, key: "R-10", title: "Launch blog post for 1.0", state: "in_progress", ownerAgentID: 14,
                points: 7, donePoints: 5, percentDone: 71, eta: "2026-10-24"),
            RequirementInfo(
                id: 11, key: "R-11", title: "Audit log of approvals", state: "plan_review", ownerAgentID: 3, points: 13,
                donePoints: 0, percentDone: 0, eta: nil),
        ]
        model.sprint = SprintInfo(
            id: 4, name: "S4", projectKey: "CIT", startsOn: now.addingTimeInterval(-5 * 86_400),
            endsOn: now.addingTimeInterval(4 * 86_400), committed: 34, completed: 23)
        model.accounts = [
            1: AccountInfo(
                id: 1, label: "claude-work", status: "limited", statusReason: "5 h window",
                statusUntil: now.addingTimeInterval(2 * 3600), windowUse: 1, windowSecs: 18_000, warnPercent: 80),
            2: AccountInfo(
                id: 2, label: "codex-pro", status: "active", statusReason: nil, statusUntil: nil, windowUse: 0.86,
                windowSecs: 18_000, warnPercent: 80),
        ]
        model.runners = [1: "hetzner-1", 2: "hetzner-2", 3: "ahmed-mbp"]
        model.limits = [
            "run.token_cap": LimitSetting(value: 200_000, source: "company:1"),
            "run.stall_after_secs": LimitSetting(value: 600, source: "project:1"),
            "budget.warn_percent": LimitSetting(value: 80, source: nil),
            "breaker.loop_threshold": LimitSetting(value: 3, source: nil),
        ]
        model.isLoaded = true
        return model
    }
}
