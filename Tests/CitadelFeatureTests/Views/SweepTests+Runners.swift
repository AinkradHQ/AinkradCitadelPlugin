import Foundation

@testable import CitadelFeature

extension SweepTests {
    /// Screens 10 Runners, 15 Accounts and the rest of 11.
    static func runnersShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let small = CGSize(width: 1200, height: 720)
        // Live runs make the sidebar taller than 720.
        let wide = CGSize(width: 1280, height: 800)
        var shots = runnerScreenShots(stage)
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
                    $0.runs[212]?.transcriptGoneReason = "pruned"
                    $0.runs[212]?.transcriptPrunedAt = Date().addingTimeInterval(-86_400)
                    $0.limits["transcript.retention_secs"] = LimitSetting(value: 30 * 86_400, source: nil)
                }, wide
            ))
        return shots
    }

    /// Screen 10 Runners and its drawers, at the prototype's window size.
    static func runnerScreenShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let window = CGSize(width: 1400, height: 900)
        func runners(_ extra: @escaping (CompanyModel) -> Void = { _ in }) -> CitadelStore {
            stage(.runners, nil) {
                CompanyFixture.runnersPage($0)
                extra($0)
            }
        }
        let registered = RegisteredRunnerInfo(
            runner: RunnerInfo(
                id: 9, name: "hetzner-3", status: "offline", healthReason: nil, lastSeenAt: nil,
                tags: ["linux", "docker"]),
            key: "rk_7f3a9c2e5b8d1f4a6c0e9b2d")
        func adding(step: Int, _ extra: @escaping (CompanyModel) -> Void = { _ in }) -> CitadelStore {
            runners {
                $0.runnersPage.adding = true
                $0.runnersPage.addDraft.name = "hetzner-3"
                $0.runnersPage.addStep = step
                if step > 0 { $0.runnersPage.registered = registered }
                extra($0)
            }
        }
        return [
            ("10-runners", runners(), window),
            ("10-runners-full", runners(), CGSize(width: 1400, height: 1900)),
            (
                "10-runners-log",
                runners {
                    $0.runnersPage.log = (
                        2,
                        [
                            "09:41:12 probe codex ok (0.88.0)", "09:56:40 run #422 claimed CIT-49",
                            "09:58:03 lease heartbeat missed ×3 → runner_lost #422",
                            "10:01:00 probe claude: not logged in (exit 1)",
                            "10:01:00 engine claude work paused on this runner",
                            "12:11:00 probe claude: not logged in (exit 1)",
                        ]
                    )
                }, window
            ),
            ("10-runners-relogin", runners { $0.runnersPage.relogin = 2 }, window),
            (
                "10-runners-relogin-waiting",
                runners {
                    $0.runnersPage.relogin = 2
                    $0.runnersPage.reloginWaiting = true
                }, window
            ),
            ("10-runners-add-1", adding(step: 0), window),
            ("10-runners-add-2", adding(step: 1), window),
            ("10-runners-add-3-wait", adding(step: 2), window),
            (
                "10-runners-add-3-joined",
                adding(step: 2) {
                    var joined = registered.runner
                    joined.status = "online"
                    joined.lastSeenAt = CompanyFixture.now
                    joined.slots = 4
                    joined.harnesses = ["claude": "2.1.296", "codex": "0.88.0", "opencode": "1.4.2"]
                    joined.logins = [
                        RunnerLoginInfo(dir: "claude", harness: "claude", state: "logged_in"),
                        RunnerLoginInfo(dir: "codex", harness: "codex", state: "logged_out"),
                    ]
                    $0.runnersPage.runners.insert(joined, at: 0)
                }, window
            ),
        ]
    }
}
