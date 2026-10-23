import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 6–9 wired: stuck-list fixes (release, retry, bump), budgets, price history, plan tier, hiring, the
/// pruned transcript and issue events naming their project.
@MainActor
final class WireNineTests: XCTestCase {
    private func store() throws -> CitadelStore {
        let settings = SettingsStore(documents: MemoryDocs())
        settings.update { $0.server = "https://citadel.example.com" }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_k", company: 1,
            session: FakeServer.session())
        let model = CompanyFixture.model()
        CompanyFixture.stuckPage(model)
        store.model = model
        return store
    }

    private func request(_ method: String, _ path: String) async throws -> (URLRequest, [String: Any]) {
        await eventually { FakeServer.requests.contains { $0.url?.path == path && $0.httpMethod == method } }
        let request = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == path && $0.httpMethod == method })
        guard let data = request.wireBody, !data.isEmpty else { return (request, [:]) }
        return (request, try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any]))
    }

    private static let issue =
        #"{"id":49,"key":"CIT-49","number":49,"title":"t","body":"","kind":"task","project_id":1,"state":"todo","next_actor":{"kind":"none"},"owner":{"kind":"user"},"labels":[],"priority":true}"#

    func testReleaseAndBumpPostToTheIssue() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { _ in .init(json: Self.issue) }
        store.releaseCheckout(model.stuck[0])
        _ = try await request("POST", "/api/v1/issues/49/release-checkout")
        store.bump(model.stuck[3])
        let (_, body) = try await request("POST", "/api/v1/issues/58/priority")
        XCTAssertEqual(body["priority"] as? Bool, true)
    }

    func testRetryPinsTheNewestEndedRunToTheChosenRunner() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { request in
            if request.url?.path == "/api/v1/companies/1/runs" {
                return .init(
                    json: #"""
                        {"items":[{"id":412,"agent_id":8,"state":"running","harness":"codex","usage":{"input_tokens":1,"output_tokens":1,"cache_tokens":0},"queued_at":"2026-10-23T09:50:00.000Z","diff_repos":[]},
                        {"id":409,"agent_id":8,"state":"runner_lost","harness":"codex","usage":{"input_tokens":1,"output_tokens":1,"cache_tokens":0},"queued_at":"2026-10-23T09:40:00.000Z","diff_repos":[]}]}
                        """#)
            }
            return .init(json: #"{"agent_id":8,"wake_id":3,"runner_id":1,"issue_id":49}"#)
        }
        let runner = RunnerInfo(
            id: 1, name: "hetzner-1", status: "online", healthReason: nil, lastSeenAt: nil, tags: [])
        XCTAssertTrue(model.stuck[0].retries)
        XCTAssertFalse(model.stuck[1].retries, "a sleeping Mac is woken, not retried")
        store.retry(model.stuck[0], on: runner)
        let (_, body) = try await request("POST", "/api/v1/runs/409/retry")
        XCTAssertEqual(body["runner_id"] as? Int, 1)
        let list = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == "/api/v1/companies/1/runs" })
        XCTAssertEqual(list.query["issue"], "49")
    }

    func testARefusedRetryCarriesTheErrorID() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { request in
            if request.url?.path == "/api/v1/companies/1/runs" {
                return .init(
                    json:
                        #"{"items":[{"id":409,"agent_id":8,"state":"failed","harness":"codex","usage":{"input_tokens":1,"output_tokens":1,"cache_tokens":0},"queued_at":"2026-10-23T09:40:00.000Z","diff_repos":[]}]}"#
                )
            }
            return .init(status: 409, json: Wire.refusal("conflict", "hetzner-1 is drained"))
        }
        let runner = RunnerInfo(
            id: 1, name: "hetzner-1", status: "online", healthReason: nil, lastSeenAt: nil, tags: [])
        store.retry(model.stuck[0], on: runner)
        await eventually { store.actionFailure != nil }
        XCTAssertEqual(store.actionFailure?.answer.errorID, "err_01JTEST")
        XCTAssertTrue(store.actionFailure?.answer.line.hasSuffix("· err_01JTEST") ?? false)
    }

    func testANewBudgetSendsItsScopePeriodAndCapAndDeleteRemovesIt() async throws {
        let store = try store()
        FakeServer.serve { request in
            request.httpMethod == "DELETE" ? .init(json: "[]") : .init(json: "{}")
        }
        store.createBudget(scope: "project:2", label: "AMC", period: "week", cap: 2_000_000, warnPercent: nil)
        let (_, body) = try await request("POST", "/api/v1/companies/1/budgets")
        XCTAssertEqual(body["period"] as? String, "week")
        XCTAssertEqual(body["token_cap"] as? Int, 2_000_000)
        XCTAssertEqual((body["scope"] as? [String: Any])?["project_id"] as? Int, 2)
        XCTAssertNil(body["warn_at_percent"], "empty warn inherits")
        let budget = try XCTUnwrap(store.model?.budgets.first)
        store.deleteBudget(budget)
        _ = try await request("DELETE", "/api/v1/budgets/\(budget.id)")
    }

    func testPriceHistoryReadsEveryVersion() async throws {
        let store = try store()
        FakeServer.serve { _ in
            .init(
                json:
                    #"[{"harness":"opencode","model":"qwen3-coder","version":1,"input_usd_per_mtok":0.3,"output_usd_per_mtok":1.2,"cache_usd_per_mtok":0,"set_at":"2026-10-12T08:00:00.000Z"}]"#
            )
        }
        let history = await store.priceHistory(harness: "opencode", model: "qwen3-coder")
        XCTAssertEqual(history.map(\.version), [1])
        let line = try XCTUnwrap(history.first?.line)
        XCTAssertTrue(line.hasPrefix("v1 · from "), line)
        XCTAssertTrue(line.contains("$1.20 out"), line)
        let sent = try XCTUnwrap(FakeServer.requests.first)
        XCTAssertEqual(sent.query["model"], "qwen3-coder")
    }

    func testAPlanTierIsStoredAsTheServerAnswers() async throws {
        let store = try store()
        let page = try XCTUnwrap(store.model?.accountsPage)
        page.accounts = [
            PoolAccount(
                id: 9, label: "claude-new", harness: "claude", billing: "subscription", status: "active",
                statusReason: nil, statusUntil: nil, configDir: "", companyIDs: [], drops: 0, companyTokens: [:],
                signalWindows: [], limits: [])
        ]
        FakeServer.serve { _ in
            .init(
                json:
                    #"{"id":9,"label":"claude-new","harness":"claude","billing":"subscription","status":"active","config_dir":"","company_ids":[],"plan_tier":"Max 20x"}"#
            )
        }
        store.setPlanTier(9, " Max 20x ")
        let (_, body) = try await request("PUT", "/api/v1/accounts/9/plan")
        XCTAssertEqual(body["plan_tier"] as? String, "Max 20x")
        await eventually { page.accounts.first?.planTier == "Max 20x" }
    }

    func testAProposedAgentOpensTheInboxWhereItsHireWaits() async throws {
        let store = try store()
        var draft = AgentDraft(name: "Wren", role: "QA", model: "claude-sonnet-4-5")
        XCTAssertNotNil(draft.problem, "a hire says why")
        draft.justification = "Reviews every PR"
        draft.runnerTags = "macos  xcode-27"
        XCTAssertNil(draft.problem)
        FakeServer.serve { _ in .init(status: 500, json: Wire.refusal("internal", "no")) }
        var done = false
        store.proposeAgent(draft) { done = true }
        let (_, body) = try await request("POST", "/api/v1/companies/1/agents")
        XCTAssertEqual(body["name"] as? String, "Wren")
        XCTAssertEqual(body["runner_tags"] as? [String], ["macos", "xcode-27"])
        await eventually { store.actionFailure != nil }
        XCTAssertFalse(done, "a refused hire keeps the sheet open")
    }

    func testTheTemplateIsAppliedThenTheInboxOpens() async throws {
        let store = try store()
        FakeServer.serve { _ in
            .init(json: #"{"department_id":1,"team_id":1,"agents":[],"hire_approval_ids":[4,5],"skills_published":3}"#)
        }
        store.useTemplate()
        _ = try await request("POST", "/api/v1/companies/1/templates/engineering")
        await eventually { store.screen == .approvals }
    }

    func testAnIssueEventInTheSprintsProjectReloadsTheSprint() throws {
        let model = CompanyFixture.model()
        let sprint = try XCTUnwrap(model.sprint)
        let project = try XCTUnwrap(model.projects.first { $0.key == sprint.projectKey })
        let other = model.projects.first { $0.key != sprint.projectKey }
        let ours = model.audited(
            action: "issue.transitioned", entity: 60, kind: "issue", run: nil,
            details: ["project_id": "\(project.id)"], at: Date())
        XCTAssertTrue(ours.contains(.sprint))
        if let other {
            let theirs = model.audited(
                action: "issue.transitioned", entity: 60, kind: "issue", run: nil,
                details: ["project_id": "\(other.id)"], at: Date())
            XCTAssertFalse(theirs.contains(.sprint))
        }
    }

    func testAPrunedTranscriptSaysHowLongTheyAreKept() {
        var run = RunInfo(id: 212, agentID: 4, state: "succeeded", harness: "claude", queuedAt: Date())
        XCTAssertEqual(run.goneLine(keptFor: nil), "Nothing of it is on the server any more, or it never started.")
        run.transcriptGoneReason = "pruned"
        XCTAssertEqual(
            run.goneLine(keptFor: LimitSetting(value: 30 * 86_400, source: nil)), "Transcripts are kept 30 days.")
    }
}

extension URLRequest {
    /// The body, whether set directly or streamed.
    fileprivate var wireBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return data
    }
}
