import Foundation

@testable import CitadelFeature

extension SweepTests {
    /// Screens 10 Runners, 15 Accounts and the rest of 11.
    static func runnersShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let small = CGSize(width: 1200, height: 720)
        // Live runs make the sidebar taller than 720.
        let wide = CGSize(width: 1280, height: 800)
        var shots: [(String, CitadelStore, CGSize)] = [
            ("10-runners", stage(.runners, nil, CompanyFixture.runnersPage), CGSize(width: 1280, height: 900))
        ]
        let accounts = stage(.accounts, nil, CompanyFixture.accountsPage)
        for event in [
            try? CompanyFixture.fallbackEvent(
                seq: 18_440, run: 424, from: "claude-work", to: "claude-personal", reason: "account at limit"),
            try? CompanyFixture.fallbackEvent(
                seq: 18_441, run: 429, from: "gpt-5.5", to: "Opus 5.5", reason: "codex-pro 5 h at 100%"),
        ].compactMap({ $0 }) {
            accounts.received(event)
        }
        shots.append(("15-accounts", accounts, CGSize(width: 1280, height: 1010)))
        shots.append(
            (
                "11-a-no-agents",
                stage(.home, nil) {
                    $0.agents = [:]
                    $0.departments = []
                    $0.runs = [:]
                    $0.requirements = []
                    $0.approvals = []
                    $0.stuck = []
                    $0.projects = []
                    $0.accounts = [:]
                }, small
            ))
        shots.append(
            (
                "11-e-inbox-zero",
                stage(.approvals, nil) {
                    $0.approvals = []
                    var merged = ApprovalInfo(
                        id: 22, kind: "pr_merge", agentID: nil, issueID: 61, requestedBy: 9, expiresAt: nil,
                        fields: [:], lists: ["prs": [["repo": "citadel"], ["repo": "plugin"]]])
                    merged.status = "approved"
                    $0.issues[61] = IssueInfo(
                        id: 61, key: "CIT-61", title: "Lease heartbeat", projectID: 1, requirementID: 12)
                    $0.answeredApprovals = [merged]
                }, wide
            ))
        shots.append(("11-f-nothing-stuck", stage(.stuck, nil) { $0.stuck = [] }, wide))
        let failed = stage(.approvals, nil, CompanyFixture.inboxPage)
        failed.actionFailure = ActionFailure(
            title: "Couldn't approve sprint CIT S5",
            answer: ServerAnswer(
                status: 409, code: "conflict", message: "Mira changed the scope 20 s ago (now 29 pts)"),
            outcome: "Nothing was approved.")
        shots.append(("11-g-action-error", failed, wide))
        shots.append(
            (
                "11-h-transcript-pruned",
                stage(.runs, .run(212)) {
                    var run = CompanyFixture.run(212, agent: 5, issue: 12, minutes: 40, tokens: 90_000)
                    run.state = "succeeded"
                    run.endedAt = run.startedAt?.addingTimeInterval(18 * 60)
                    run.costMicros = 1_120_000
                    $0.runs[212] = run
                    $0.issues[12] = IssueInfo(
                        id: 12, key: "CIT-12", title: "Org chart API", projectID: 1, requirementID: nil)
                    $0.transcripts[212] = []
                }, wide
            ))
        return shots
    }
}
