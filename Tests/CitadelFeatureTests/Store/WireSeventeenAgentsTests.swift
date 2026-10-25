import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 17, agents: edit, wake now, terminate and the richer hire proposal.
@MainActor
final class WireSeventeenAgentsTests: XCTestCase {
    private static let agent = """
        {"id":5,"company_id":1,"name":"Wren","role":"dev","org_role":"none","status":"active","harness":"codex","model":"gpt-5.5",
        "runner_tags":["macos"],"status":"active","appearance":{"figure_version":"1","palette_id":"jade"},"figure_state":"idle",
        "hired_at":"2026-10-01T10:00:00.000Z","run_token_cap":0,"issue_token_cap":0,"reports_to":2,
        "description":"Builds the app","effort":"high","sandbox":"read-only","instructions":"Be terse",
        "guidelines":["Write tests"]}
        """

    func testEditingAnAgentPatchesItAndShowsTheSavedFields() async throws {
        let store = try Wire17.store()
        let wren = try XCTUnwrap(store.model?.agents[5])
        FakeServer.serve { _ in .init(json: Self.agent) }
        store.edit(
            wren, AgentPatch(harness: "codex", model: "gpt-5.5", effort: "high", about: "Builds the app"),
            title: "Model updated")
        let body = try await Wire17.sent("PATCH", "/api/v1/agents/5")
        XCTAssertEqual(body["harness"] as? String, "codex")
        XCTAssertEqual(body["effort"] as? String, "high")
        XCTAssertEqual(body["description"] as? String, "Builds the app")
        XCTAssertNil(body["sandbox"], "a field left alone is not sent")
        await eventually { store.model?.agents[5]?.effort == "high" }
        let saved = try XCTUnwrap(store.model?.agents[5])
        XCTAssertEqual(saved.about, "Builds the app")
        XCTAssertEqual(saved.sandbox, "read-only")
        XCTAssertEqual(saved.instructions, "Be terse")
        XCTAssertEqual(saved.guidelines, ["Write tests"])
    }

    func testAnOlderServerIsNeverAskedToEditWakeOrTerminate() async throws {
        let store = try Wire17.store(minor: 16)
        let wren = try XCTUnwrap(store.model?.agents[5])
        FakeServer.serve { _ in .init(status: 404, json: Wire.refusal("not_found", "no such route")) }
        store.edit(wren, AgentPatch(about: "x"), title: "t")
        store.wake(wren)
        store.terminate(wren, reason: "gone")
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(
            FakeServer.requests.filter { $0.httpMethod != "GET" }.isEmpty,
            "no write reaches an endpoint a minor-16 server lacks")
        XCTAssertNil(store.actionFailure)
    }

    func testWakeNowPostsAndATerminationSendsItsReason() async throws {
        let store = try Wire17.store()
        let wren = try XCTUnwrap(store.model?.agents[5])
        FakeServer.serve { _ in .init(json: Self.agent) }
        store.wake(wren)
        _ = try await Wire17.sent("POST", "/api/v1/agents/5/wake")
        store.terminate(wren, reason: "  no longer needed ")
        let body = try await Wire17.sent("POST", "/api/v1/agents/5/terminate")
        XCTAssertEqual(body["reason"] as? String, "no longer needed")
    }

    func testAWakeTheServerRefusesShowsItsMessage() async throws {
        let store = try Wire17.store()
        let wren = try XCTUnwrap(store.model?.agents[5])
        FakeServer.serve { _ in .init(status: 409, json: Wire.refusal("conflict", "Wren is paused")) }
        store.wake(wren)
        await eventually { store.actionFailure != nil }
        XCTAssertEqual(store.actionFailure?.answer.message, "Wren is paused")
    }

    func testAHireProposalCarriesTheNewFields() throws {
        var draft = AgentDraft()
        draft.name = "Nova"
        draft.role = "QA"
        draft.model = "opus-5.5"
        draft.justification = "needed"
        draft.description = "Tests things"
        draft.effort = "low"
        draft.sandbox = "full-access"
        draft.instructions = "Test it"
        draft.guidelines = [" Write tests ", ""]
        draft.teamID = 4
        draft.paletteID = "jade"
        let body = draft.body
        XCTAssertEqual(body.description, "Tests things")
        XCTAssertEqual(body.effort?.word, "low")
        XCTAssertEqual(body.sandbox?.word, "full-access")
        XCTAssertEqual(body.guidelines, ["Write tests"])
        XCTAssertEqual(body.teamId, 4)
        XCTAssertEqual(body.paletteId, "jade")
        XCTAssertNil(AgentDraft().body.description, "an older server's proposal stays as it was")
    }
}
