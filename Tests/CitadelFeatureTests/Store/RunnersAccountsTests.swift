import AinkradAppKit
import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// Screens 10, 15 and the 11 states: runner state and disk, account windows and health, scope chips, the
/// fallback chain's order, and the empty / error conditions. Every time is fixed — never `Date()`.
@MainActor
final class RunnersAccountsTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    // MARK: - Runners

    func testRunnerReasonsFollowTheState() throws {
        var runner = RunnerInfo(
            id: 2, name: "hetzner-2", status: "unhealthy",
            healthReason: "Claude login expired 2h 10m ago. The engine stopped sending it Claude work.",
            lastSeenAt: now, tags: [])
        let unhealthy = try XCTUnwrap(runner.reason(now: now))
        XCTAssertEqual(unhealthy.title, "Claude login expired 2h 10m ago.")
        XCTAssertEqual(unhealthy.detail, "The engine stopped sending it Claude work.")
        runner.status = "offline"
        runner.lastSeenAt = now.addingTimeInterval(-3 * 86_400 - 60)
        XCTAssertEqual(runner.reason(now: now)?.title, "No heartbeat for 3 days.")
        runner.status = "online"
        XCTAssertNil(runner.reason(now: now))
    }

    func testDiskSplitsIdleFromActiveAndCountsDownFromTheMeasurement() {
        let measured = now.addingTimeInterval(-600)
        let disk = RunnerDiskInfo(
            capBytes: 50_000_000_000, used: 43_800_000_000, shared: 31_000_000_000, active: 2_000_000_000,
            idle: 10_800_000_000, evictPercent: 90, full: false, measuredAt: measured,
            worktrees: [
                WorktreeDiskInfo(issueID: 9, bytes: 2, active: true, idleSecs: 0, removedInSecs: nil),
                WorktreeDiskInfo(issueID: 63, bytes: 1, active: false, idleSecs: 3_600, removedInSecs: 78_000),
                WorktreeDiskInfo(issueID: 61, bytes: 3, active: false, idleSecs: 72_000, removedInSecs: 12_120),
            ])
        XCTAssertEqual(disk.activeCount, 1)
        XCTAssertEqual(disk.idleWorktrees.map(\.issueID), [61, 63], "oldest idle first: evicted first")
        XCTAssertEqual(disk.fraction, 0.876, accuracy: 0.001)
        XCTAssertTrue(disk.isNearCap, "88% is within 5 points of the 90% evict line")
        let first = disk.idleWorktrees[0]
        // 12,120 s after a measurement 600 s ago: 3h 12m left.
        XCTAssertEqual(first.removalCountdown(measuredAt: measured, now: now), "removed in 3h 12m")
        XCTAssertNil(disk.worktrees[0].removalCountdown(measuredAt: measured, now: now), "active: no countdown")
        XCTAssertEqual(
            first.line(key: "CIT-61", repos: ["citadel", "plugin"]), "cit-61 · citadel + plugin · 2 worktrees · idle")
        XCTAssertEqual(disk.worktrees[1].line(key: "CIT-63", repos: ["citadel"]), "cit-63 · citadel · idle")
    }

    func testRunnerLimitsResolveServerToRunner() {
        let model = CompanyFixture.model()
        CompanyFixture.runnersPage(model)
        let page = model.runnersPage
        let key = "runner.disk_cap_bytes"
        let server = page.serverSettings[key]
        XCTAssertEqual(page.settings[1]?[key]?.chip(at: "runner:1", inherited: server), .inherited(from: "server"))
        XCTAssertEqual(
            page.settings[2]?[key]?.chip(at: "runner:2", inherited: server),
            .overridden(at: "runner", inheritedValue: "server 50 GB"))
        XCTAssertEqual(page.counts.online, 2)
        XCTAssertEqual(page.counts.unhealthy, 1)
        XCTAssertEqual(page.counts.offline, 1)
    }

    // MARK: - Accounts

    func testAccountHealthAndCompanyShares() {
        let model = CompanyFixture.model()
        CompanyFixture.accountsPage(model)
        let health = model.accountsPage.accounts.map(\.health)
        XCTAssertEqual(health, [.healthy, .atLimit, .flaky, .healthy, .healthy])
        let personal = model.accountsPage.accounts[0]
        XCTAssertEqual(personal.share(of: 1), 82)
        XCTAssertEqual(personal.share(of: 3), 18)
        XCTAssertNil(model.accountsPage.accounts[4].share(of: 1), "nothing used yet: no share")
        XCTAssertEqual(model.accountsPage.warnPercent(2), 70, "claude-work's own warn line")
        XCTAssertEqual(model.accountsPage.warnPercent(1), 80)
        XCTAssertEqual(
            model.accountsPage.visible(company: 2).map(\.label), ["claude-work", "codex-pro", "anthropic-api"])
    }

    func testWindowBarsCarryTheirWarnMarkLimitToneAndReset() throws {
        let account = PoolAccount(
            id: 1, label: "codex-pro", harness: "codex", billing: "subscription", status: "active", statusReason: nil,
            statusUntil: nil, configDir: "", companyIDs: [1], drops: 0, companyTokens: [:],
            signalWindows: [SignalWindow(name: "five_hour", utilization: 1.0, resetsAt: now.addingTimeInterval(3_600))],
            limits: [
                AccountLimitInfo(
                    windowSecs: 604_800, unit: "tokens", max: 20_000_000, warnPercent: 75, used: 11_000_000)
            ])
        let bars = account.windows(warnPercent: 80)
        XCTAssertEqual(bars.map(\.label), ["5 h", "7 d"])
        XCTAssertEqual(bars[0].warnFraction, 0.8)
        XCTAssertTrue(bars[0].isAtLimit)
        XCTAssertEqual(bars[0].tone, .warning, "at the limit it is skipped, amber, never red")
        XCTAssertEqual(bars[1].fraction, 0.55, accuracy: 0.0001)
        XCTAssertEqual(bars[1].warnFraction, 0.75, "a counted limit keeps its own warn line")
        XCTAssertNil(bars[1].tone)
        XCTAssertNil(bars[1].resetText(now: now), "a counted window rolls: no reset")
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let reset = try XCTUnwrap(bars[0].resetText(now: now, calendar: calendar))
        let time = now.addingTimeInterval(3_600).formatted(
            Date.FormatStyle(date: .omitted, time: .shortened, timeZone: calendar.timeZone))
        XCTAssertEqual(reset, "↺ \(time)", "within the day: the time only")
        let weekly = UsageWindow(
            id: "w", label: "Weekly", fraction: 0.4, warnFraction: 0.8, resetsAt: now.addingTimeInterval(3 * 86_400),
            limit: nil)
        XCTAssertNotEqual(weekly.resetText(now: now, calendar: calendar), "↺ \(time)")
        XCTAssertTrue(weekly.resetText(now: now, calendar: calendar)?.hasPrefix("↺ ") ?? false)
    }

    func testTheHarnessSignalParses() {
        let windows = PoolAccount.signalWindows([
            "type": "rate_limit",
            "windows": [
                ["name": "seven_day", "utilization": 0.48, "resets_at": 1_800_300_000] as [String: (any Sendable)?],
                ["name": "five_hour", "utilization": 0.71] as [String: (any Sendable)?],
            ] as [(any Sendable)?],
        ])
        XCTAssertEqual(windows.map(\.label), ["5 h", "Weekly"])
        XCTAssertEqual(windows[1].resetsAt, Date(timeIntervalSince1970: 1_800_300_000))
        XCTAssertNil(windows[0].resetsAt)
        XCTAssertEqual(SignalWindow(name: "seven_day_opus", utilization: 0, resetsAt: nil).label, "Weekly · opus")
        XCTAssertTrue(PoolAccount.signalWindows(nil).isEmpty)
    }

    func testTypedWindowsParse() throws {
        let tokens = try XCTUnwrap(AccountLimitInfo.parse("5 h ≤ 3M tok"))
        XCTAssertEqual(tokens.windowSecs, 18_000)
        XCTAssertEqual(tokens.max, 3_000_000)
        XCTAssertEqual(tokens.unit, "tokens")
        let messages = try XCTUnwrap(AccountLimitInfo.parse("7d <= 200 msg"))
        XCTAssertEqual(messages.windowSecs, 604_800)
        XCTAssertEqual(messages.max, 200)
        XCTAssertEqual(messages.unit, "messages")
        XCTAssertNil(AccountLimitInfo.parse("5 h ≤ signal"))
        XCTAssertNil(AccountLimitInfo.parse("forever"))
        XCTAssertEqual(
            AccountLimitInfo(windowSecs: 18_000, unit: "tokens", max: 3_000_000, warnPercent: 80, used: 0).text,
            "5 h ≤ 3M tok")
    }

    func testAccountLimitsResolveServerToAccount() {
        let model = CompanyFixture.model()
        CompanyFixture.accountsPage(model)
        let page = model.accountsPage
        let warn = page.serverSettings["account.warn_percent"]
        XCTAssertEqual(
            page.settings[2]?["account.warn_percent"]?.chip(at: "account:2", inherited: warn),
            .overridden(at: "account", inheritedValue: "server 80%"))
        XCTAssertEqual(
            page.settings[1]?["account.warn_percent"]?.chip(at: "account:1", inherited: warn),
            .inherited(from: "server"))
    }

    // MARK: - Fallback chain

    func testAReorderKeepsTheAgentsOwnEntryFirstAndSendsOnlyTheFallbacks() {
        let own = FallbackEntry(harness: "codex", model: "gpt-5.5", isOwn: true)
        let opus = FallbackEntry(harness: "claude", model: "opus-5.5")
        let qwen = FallbackEntry(harness: "opencode", model: "qwen3-coder")
        // The person dragged qwen to the very top.
        let dragged = reorderedItems([own, opus, qwen], moving: 2, to: 0)
        let saved = FallbackEntry.reordered(dragged)
        XCTAssertEqual(saved.map(\.model), ["gpt-5.5", "qwen3-coder", "opus-5.5"])
        let body = FallbackEntry.body(saved)
        XCTAssertEqual(body.map(\.model), ["qwen3-coder", "opus-5.5"])
        XCTAssertEqual(body.map(\.harness.word), ["opencode", "claude"])
    }

    func testSavingTheChainPutsTheFallbacksInTheirNewOrder() async throws {
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/agents/4/fallbacks", request.httpMethod == "PUT" else {
                return .init(status: 404)
            }
            return .init(
                json: #"[{"harness":"opencode","model":"qwen3-coder"},{"harness":"claude","model":"opus-5.5"}]"#)
        }
        let (store, model) = try connectedStore()
        CompanyFixture.accountsPage(model)
        let chain = model.accountsPage.chain
        store.saveChain(reorderedItems(chain, moving: 3, to: 1).filter { $0.model != "sonnet-5" })
        await eventually { FakeServer.requests.contains { $0.httpMethod == "PUT" } }
        XCTAssertEqual(model.accountsPage.chain.map(\.model), ["gpt-5.5", "qwen3-coder", "opus-5.5"])
        let request = try XCTUnwrap(FakeServer.requests.first { $0.httpMethod == "PUT" })
        let sent = try XCTUnwrap(
            JSONSerialization.jsonObject(with: try XCTUnwrap(request.bodyData)) as? [[String: String]])
        XCTAssertEqual(sent.map { $0["model"] }, ["qwen3-coder", "opus-5.5"])
    }

    func testLastFallbacksReadTheStreamNewestFirst() throws {
        let events = try [
            CompanyFixture.fallbackEvent(
                seq: 1, run: 424, from: "claude-work", to: "claude-personal", reason: "at limit"),
            CompanyFixture.fallbackEvent(seq: 2, run: 429, from: "gpt-5.5", to: "Opus 5.5", reason: "5 h at 100%"),
        ]
        let moves = FallbackMove.recent(events)
        XCTAssertEqual(moves.map(\.run), [429, 424])
        XCTAssertEqual(moves[0].from, "gpt-5.5")
        XCTAssertEqual(moves[0].to, "Opus 5.5")
        XCTAssertEqual(moves[0].why, "5 h at 100%")
    }

    // MARK: - 11: empty and error states

    func testInboxZeroNamesTheLastDecision() {
        let model = CompanyFixture.model()
        XCTAssertNil(model.lastDecisionLine())
        model.issues[61] = IssueInfo(id: 61, key: "CIT-61", title: "Lease", projectID: 1, requirementID: nil)
        var merged = ApprovalInfo(
            id: 22, kind: "pr_merge", agentID: nil, issueID: 61, requestedBy: 9, expiresAt: nil, fields: [:],
            lists: ["prs": [["repo": "citadel"], ["repo": "plugin"]]])
        merged.status = "approved"
        model.answeredApprovals = [merged]
        XCTAssertEqual(model.lastDecisionLine(), "Last decision: merged CIT-61 (2 PRs).")
    }

    func testAnEndedRunWithNoChunksHasNoTranscript() {
        var run = CompanyFixture.run(212, agent: 5, issue: 12, minutes: 40, tokens: 1)
        XCTAssertFalse(run.hasNoTranscript([]), "a live run is still starting")
        run.state = "succeeded"
        XCTAssertTrue(run.hasNoTranscript([]))
        XCTAssertFalse(run.hasNoTranscript(nil), "not loaded yet")
        run.startedAt = now
        run.endedAt = now.addingTimeInterval(18 * 60)
        run.costMicros = 1_120_000
        XCTAssertEqual(run.summaryLine(issue: "CIT-12"), "succeeded · 18m · $1.12 · CIT-12")
    }

    func testARefusedDecisionSaysWhatTheServerAnsweredAndChangesNothing() async throws {
        FakeServer.serve { _ in
            .init(status: 409, json: Wire.refusal("conflict", "Mira changed the scope 20 s ago (now 29 pts)"))
        }
        let (store, model) = try connectedStore()
        CompanyFixture.inboxPage(model)
        let sprint = try XCTUnwrap(model.approvals.first { $0.kind == "sprint_commit" })
        store.decide(sprint, approve: true)
        await eventually { store.actionFailure != nil }
        let failure = try XCTUnwrap(store.actionFailure)
        XCTAssertEqual(failure.title, "Couldn't approve sprint CIT S5")
        XCTAssertEqual(
            failure.message,
            "The server answered 409: Mira changed the scope 20 s ago (now 29 pts). Nothing was approved.")
        XCTAssertEqual(failure.answer.line, "409 conflict: Mira changed the scope 20 s ago (now 29 pts) · err_01JTEST")
        XCTAssertTrue(model.approvals.contains { $0.id == sprint.id }, "nothing was approved")
    }

    private func connectedStore() throws -> (CitadelStore, CompanyModel) {
        let settings = SettingsStore(documents: MemoryDocs())
        settings.update { $0.server = "https://citadel.example.com" }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_k", company: 1,
            session: FakeServer.session())
        let model = CompanyFixture.model()
        store.model = model
        return (store, model)
    }
}

extension URLRequest {
    /// The body, whether URLSession kept it as data or as a stream.
    fileprivate var bodyData: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
