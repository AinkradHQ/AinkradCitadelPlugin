import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 18, tranche B2: chain presets (read, write, assign, default) and roles.
@MainActor
final class WireEighteenChainsTests: XCTestCase {
    private let presetJSON =
        ##"{"id":3,"company_id":1,"name":"Codex first","color":"#2563eb","description":"","is_default":true,"entries":[{"harness":"codex","model":"gpt-5.5","account_id":7},{"harness":"claude","model":"opus-5.5"}]}"##

    func testPresetsAreReadFromMinor18AndNotBefore() async throws {
        let store = try Wire17.store(minor: 18)
        FakeServer.serve { _ in .init(json: "[\(self.presetJSON)]") }
        store.loadChainPresets()
        await eventually { store.model?.chainPresets.count == 1 }
        let preset = try XCTUnwrap(store.model?.chainPresets.first)
        XCTAssertEqual(preset.entries.map(\.model), ["gpt-5.5", "opus-5.5"])
        XCTAssertEqual(preset.entries.first?.accountID, 7)
        XCTAssertEqual(store.model?.defaultChainPreset?.id, 3)

        let older = try Wire17.store(minor: 17)
        FakeServer.serve { _ in .init(json: "[\(self.presetJSON)]") }
        older.loadChainPresets()
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(FakeServer.requests.isEmpty, "an older server is never asked")
        XCTAssertEqual(older.model?.chainPresets, [])
    }

    func testANewPresetIsPostedWithItsColourAndEntries() async throws {
        let store = try Wire17.store(minor: 18)
        FakeServer.serve { _ in .init(json: self.presetJSON) }
        let draft = ChainPresetInfo(
            id: 0, name: " Cheap ", description: "", colorHex: "#10b981", isDefault: false,
            entries: [FallbackEntry(harness: "opencode", model: "qwen3-coder")])
        store.saveChainPreset(draft, isNew: true)
        let body = try await Wire17.sent("POST", "/api/v1/companies/1/chain-presets")
        XCTAssertEqual(body["name"] as? String, "Cheap")
        XCTAssertEqual(body["color"] as? String, "#10b981")
        XCTAssertEqual((body["entries"] as? [[String: Any]])?.first?["model"] as? String, "qwen3-coder")
    }

    func testAssigningSendsThePresetAndALeftOutAgentGetsACopy() async throws {
        let store = try Wire17.store(minor: 18)
        let model = try XCTUnwrap(store.model)
        let preset = ChainPresetInfo(
            id: 3, name: "Codex first", description: "", colorHex: nil, isDefault: false,
            entries: [FallbackEntry(harness: "claude", model: "opus-5.5", accountID: 7)])
        model.chainPresets = [preset]
        model.agents[4]?.chainPresetID = 3
        FakeServer.serve { _ in .init(json: #"{"preset_id":3,"entries":[{"harness":"claude","model":"opus-5.5"}]}"#) }
        store.assign(preset, to: [15])
        let picked = try await Wire17.sent("PUT", "/api/v1/agents/15/chain")
        XCTAssertEqual(picked["preset_id"] as? Int, 3)
        let left = try await Wire17.sent("PUT", "/api/v1/agents/4/chain")
        XCTAssertNil(left["preset_id"])
        let entries = try XCTUnwrap(left["entries"] as? [[String: Any]])
        XCTAssertNil(entries.first?["account_id"], "an agent's own entries carry no pin")
    }

    func testAnOlderServerGetsNoChainWrite() async throws {
        let store = try Wire17.store(minor: 17)
        let agent = try XCTUnwrap(store.model?.agents[4])
        FakeServer.serve { _ in .init(json: "{}") }
        store.saveChainPreset(
            ChainPresetInfo(id: 0, name: "X", description: "", colorHex: nil, isDefault: false, entries: []),
            isNew: true)
        store.customizeChain(of: agent, entries: [])
        store.saveRole(
            RoleInfo(id: 0, name: "Ops", purpose: "", icon: "gear", skills: [], instructions: ""), isNew: true
        ) {}
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(FakeServer.requests.isEmpty)
    }

    func testTheAgentOnNoChainFallsToTheDefaultPreset() throws {
        let model = try XCTUnwrap(Wire17.store(minor: 18).model)
        model.chainPresets = [
            ChainPresetInfo(id: 3, name: "Codex first", description: "", colorHex: nil, isDefault: true, entries: [])
        ]
        let agent = try XCTUnwrap(model.agents[4])
        XCTAssertEqual(model.chainPreset(of: agent, fallbacks: [])?.id, 3)
        XCTAssertNil(model.chainPreset(of: agent, fallbacks: [FallbackEntry(harness: "codex", model: "gpt-5.5")]))
    }

    func testARoleIsPostedAndAnEditIsPut() async throws {
        let store = try Wire17.store(minor: 18)
        let role =
            #"{"id":9,"company_id":1,"name":"Ops","purpose":"Keeps CI green","icon":"gear","skills":["ci"],"instructions":"Fix it","budget_tokens":4000000}"#
        FakeServer.serve { _ in .init(json: role) }
        let draft = RoleInfo(
            id: 0, name: "Ops", purpose: "Keeps CI green", icon: "gear", skills: ["ci"], instructions: "Fix it",
            harness: "codex", model: "gpt-5.5", budgetTokens: 4_000_000)
        store.saveRole(draft, isNew: true) {}
        let body = try await Wire17.sent("POST", "/api/v1/companies/1/roles")
        XCTAssertEqual(body["name"] as? String, "Ops")
        XCTAssertEqual(body["budget_tokens"] as? Int, 4_000_000)
        XCTAssertEqual(body["harness"] as? String, "codex")
        var edit = draft
        edit = RoleInfo(
            id: 9, name: "Ops", purpose: edit.purpose, icon: edit.icon, skills: edit.skills,
            instructions: edit.instructions)
        store.saveRole(edit, isNew: false) {}
        _ = try await Wire17.sent("PUT", "/api/v1/roles/9")
    }
}
