import AinkradAppKit
import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// Server → screen mapping (figure state, palette, harness, budget levels, the needs list) and the event stream's
/// updates reaching the company the screens read.
@MainActor
final class CompanyModelTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try EventFrame.decoder.decode(T.self, from: Data(json.utf8))
    }

    private func agentJSON(figure: String, palette: String, status: String = "active", avatar: String = "null")
        -> String
    {
        #"{"id":4,"company_id":1,"name":"Kestrel","role":"dev","org_role":"none","harness":"codex","model":"gpt-5.5","runner_tags":["linux"],"status":"\#(status)","appearance":{"figure_version":"b1","palette_id":"\#(palette)"},"figure_state":"\#(figure)","avatar_url":\#(avatar),"hired_at":"2026-10-20T09:00:00.000Z","run_token_cap":200000,"issue_token_cap":2000000}"#
    }

    // MARK: - Mapping

    func testAnAgentIsDrawnAsItsFigureWithItsPaletteStateHarnessAndImage() throws {
        let agent = AgentInfo(
            try decode(
                Schemas.Agent.self,
                agentJSON(figure: "working", palette: "ember", avatar: #""/api/v1/agents/4/avatar""#)))
        XCTAssertEqual(agent.figure, .working)
        XCTAssertEqual(agent.palette, .ember)
        XCTAssertEqual(agent.figureHarness, .codex)
        XCTAssertEqual(agent.harnessName, "Codex")
        XCTAssertEqual(agent.avatarPath, "/api/v1/agents/4/avatar")
    }

    func testPaletteFallsBackAndPausedAgentsAreMuted() throws {
        XCTAssertEqual(
            AgentInfo(try decode(Schemas.Agent.self, agentJSON(figure: "idle", palette: "no-such"))).palette, .neonTide)
        let paused = AgentInfo(
            try decode(Schemas.Agent.self, agentJSON(figure: "sleepy", palette: "ember", status: "paused")))
        XCTAssertEqual(paused.palette, .muted)
        XCTAssertEqual(paused.figure, .sleepy)
    }

    func testAnUnknownFigureStateIsIdleAndAHardErrorIsToldFromAStall() throws {
        XCTAssertEqual(
            AgentInfo(try decode(Schemas.Agent.self, agentJSON(figure: "dancing", palette: "ember"))).figure, .idle)
        XCTAssertEqual(AgentLook.figure("confused", lastRunState: "runner_lost"), .error)
        XCTAssertEqual(AgentLook.figure("confused", lastRunState: "failed"), .error)
        XCTAssertEqual(AgentLook.figure("confused", lastRunState: "cancelled"), .confused)
        XCTAssertEqual(AgentLook.figure("confused"), .confused)
        XCTAssertNil(AgentLook.harness("cursor"))
        XCTAssertEqual(AgentLook.harness("opencode"), .openCode)
    }

    func testBudgetLevelsFollowTheWarnMarkAndTheCap() {
        let budget = BudgetInfo(
            id: 1, label: "Quill", scope: "agent:15", period: "day", periodKey: "2026-10-23", spent: 168_000,
            cap: 200_000, warnPercent: 80)
        XCTAssertEqual(
            budgetBarState(value: Double(budget.spent), limit: Double(budget.cap), warnFraction: budget.warnFraction)
                .level, .warning)
        XCTAssertEqual(budgetBarState(value: 100, limit: 200, warnFraction: 0.8).level, .ok)
        XCTAssertEqual(budgetBarState(value: 200, limit: 200, warnFraction: 0.8).level, .over)
    }

    func testABudgetStandingCountsRaisedTokensInItsCap() throws {
        let standing = try decode(
            Schemas.BudgetStanding.self,
            #"{"budget_id":3,"scope":{"kind":"agent","agent_id":4},"period":"month","token_cap":1000,"warn_at_percent":80,"hard_stop":true,"period_key":"2026-10","spent":900,"raised":500}"#
        )
        let budget = BudgetInfo(standing) { $0 == "agent:4" ? "Kestrel" : "?" }
        XCTAssertEqual(budget.label, "Kestrel")
        XCTAssertEqual(budget.cap, 1500)
        XCTAssertEqual(budget.scope, "agent:4")
    }

    func testRunCardsGoAmberWhenWaitingAndRedNearTheStallLimit() {
        let model = CompanyFixture.model()
        let now = CompanyFixture.now
        XCTAssertEqual(model.cardState(of: model.runs[419]!, now: now).word, "waiting")
        XCTAssertEqual(model.cardState(of: model.runs[430]!, now: now).word, "stalled")
        XCTAssertNil(model.cardState(of: model.runs[418]!, now: now).word)
        XCTAssertEqual(liveness(silentFor: 479, limit: 600), .fine)
        XCTAssertEqual(liveness(silentFor: 480, limit: 600), .nearStall)
        XCTAssertEqual(liveness(silentFor: 600, limit: 600), .stalled)
        XCTAssertEqual(liveness(silentFor: 9_999, limit: nil), .fine)
    }

    func testNeedsYouListsWhatBlocksARunFirstThenASprint() {
        let items = CompanyFixture.model().needsItems(now: CompanyFixture.now)
        XCTAssertEqual(items.map(\.rank), items.map(\.rank).sorted(), "ordered by what it blocks")
        XCTAssertEqual(items.first?.title, "Quill asks to run WebFetch")
        XCTAssertTrue(items.contains { $0.title == "Rook's run on CIT-64 is about to stall" && $0.rank == 0 })
        XCTAssertTrue(items.contains { $0.title == "CIT-49 has no next actor for 2h" })
        XCTAssertTrue(items.contains { $0.id == "budget-1" }, "a budget past its warn mark")
        XCTAssertFalse(items.contains { $0.id == "budget-3" }, "a budget under its warn mark")
    }

    func testOrgLinesSayWhatEachAgentIsOn() {
        let model = CompanyFixture.model()
        XCTAssertEqual(model.orgLine(model.agents[4]!).text, "Codex · gpt-5.5 · CIT-42")
        XCTAssertEqual(model.orgLine(model.agents[15]!).tone, .warning)
        XCTAssertEqual(model.orgLine(model.agents[13]!).text, "Codex · gpt-5.5 · paused")
        XCTAssertTrue(OrgFilter.waiting.matches(model.agents[15]!))
        XCTAssertFalse(OrgFilter.working.matches(model.agents[15]!))
    }

    // MARK: - The event stream

    private func event(_ payload: String, seq: Int64 = 9) throws -> Schemas.Event {
        try decode(Schemas.Event.self, #"{"seq":\#(seq),"at":"2026-10-23T10:00:00.000Z","payload":\#(payload)}"#)
    }

    func testATranscriptChunkMovesTheLiveToolLineAndAppendsToALoadedTranscript() throws {
        let model = CompanyFixture.model()
        model.transcripts[418] = []
        // The fixture's progress time is relative to the real clock; pin it before the chunk's
        // fixed time so the assertion doesn't depend on the time of day.
        model.runs[418]?.lastProgressAt = Date(timeIntervalSince1970: 0)
        let reloads = model.apply(
            try event(
                #"{"type":"transcript","run_id":418,"chunk":{"seq":3,"at":"2026-10-23T10:00:00.000Z","kind":"tool_use","payload":{"type":"tool_use","id":"t1","name":"Read","input":{"file_path":"crates/citadel-server/src/stream.rs"}}}}"#
            ))
        XCTAssertEqual(model.toolNow[418], "Read crates/citadel-server/src/stream.rs")
        XCTAssertEqual(model.transcripts[418]?.map(\.seq), [3])
        XCTAssertEqual(model.runs[418]?.lastProgressAt, try decode(Date.self, #""2026-10-23T10:00:00.000Z""#))
        XCTAssertTrue(reloads.isEmpty, "a tool call needs no read")

        _ = model.apply(
            try event(
                #"{"type":"transcript","run_id":418,"chunk":{"seq":3,"at":"2026-10-23T10:00:00.000Z","kind":"tool_use","payload":{}}}"#
            ))
        XCTAssertEqual(model.transcripts[418]?.count, 1, "a replayed chunk is stored once")
    }

    func testAuditEventsNameWhatToReadAgain() throws {
        let model = CompanyFixture.model()
        func audit(_ action: String, entity: Int64? = nil, run: Int64? = nil) throws -> Set<Reload> {
            let entityJSON = entity.map { #","entity_id":\#($0),"entity_kind":"issue""# } ?? ""
            let runJSON = run.map { #","run_id":\#($0)"# } ?? ""
            return model.apply(
                try event(
                    #"{"type":"audit","audit_seq":1,"action":"\#(action)","actor":{"kind":"system"},"details":{"reason":"overloaded"}\#(entityJSON)\#(runJSON)}"#
                ))
        }
        XCTAssertEqual(try audit("approval.approved"), [.approvals])
        XCTAssertEqual(try audit("run.succeeded", run: 418), [.run(418), .costs])
        XCTAssertEqual(try audit("issue.blocked", entity: 77), [.stuck, .issue(77)])
        XCTAssertEqual(try audit("budget.warning"), [.costs])
        XCTAssertEqual(try audit("requirement.plan_submitted"), [.requirements, .questions])
        XCTAssertEqual(try audit("weather.sunny"), [])
        _ = try audit("run.provider_dropped", run: 418)
        XCTAssertEqual(model.notes[418]?.first?.text.hasPrefix("Provider dropped (overloaded)"), true)
        XCTAssertEqual(model.apply(try event(Wire.wakePayload)), [.agent(3)])
    }

    func testTheStoreFoldsStreamEventsIntoTheCompanyAndReadsTheRunAgain() async throws {
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/runs/418" else { return .init(status: 404) }
            return .init(
                json:
                    #"{"id":418,"agent_id":4,"state":"succeeded","harness":"codex","usage":{"input_tokens":90000,"output_tokens":10000,"cache_tokens":0},"queued_at":"2026-10-23T09:50:00.000Z","diff_repos":[]}"#
            )
        }
        let settings = SettingsStore(documents: MemoryDocs())
        settings.update { $0.server = "https://citadel.example.com" }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_FAKE_fixture", company: 1,
            session: FakeServer.session())
        let model = CompanyFixture.model()
        store.model = model

        store.received(
            try event(
                #"{"type":"transcript","run_id":418,"chunk":{"seq":4,"at":"2026-10-23T10:00:00.000Z","kind":"usage","payload":{"type":"usage","input":10,"output":2}}}"#
            ))
        XCTAssertEqual(model.toolNow[418], "Bash cargo test -p citadel-server replay", "usage is not a tool call")
        await eventually { model.runs[418]?.state == "succeeded" }
        XCTAssertEqual(model.runs[418]?.tokens, 100_000)
        XCTAssertFalse(model.liveRuns.contains { $0.id == 418 }, "an ended run leaves the live strip")
    }
}

extension Wire {
    static let wakePayload = #"{"type":"wake","wake_id":1,"agent_id":3,"source":"timer","reason":"tick","issue_id":42}"#
}
