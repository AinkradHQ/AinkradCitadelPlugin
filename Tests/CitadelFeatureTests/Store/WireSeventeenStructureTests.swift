import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 17, org structure: departments, teams and seats.
@MainActor
final class WireSeventeenStructureTests: XCTestCase {
    func testADepartmentIsCreatedWithItsHeadAndAbout() async throws {
        let store = try Wire17.store()
        FakeServer.serve { _ in .init(json: #"{"id":8,"name":"Sales","about":"Sells","head_agent_id":3,"teams":[]}"#) }
        var closed = false
        store.saveDepartment(nil, name: " Sales ", about: "Sells", head: 3) { closed = true }
        let body = try await Wire17.sent("POST", "/api/v1/companies/1/departments")
        XCTAssertEqual(body["name"] as? String, "Sales")
        XCTAssertEqual(body["about"] as? String, "Sells")
        XCTAssertEqual(body["head_agent_id"] as? Int, 3)
        await eventually { closed }
    }

    func testRenamingADepartmentPatchesAndADuplicateNameShowsTheServersWords() async throws {
        let store = try Wire17.store()
        FakeServer.serve { _ in .init(status: 409, json: Wire.refusal("conflict", "a department named Sales exists")) }
        store.saveDepartment(2, name: "Sales", about: "", head: nil) {}
        let body = try await Wire17.sent("PATCH", "/api/v1/departments/2")
        XCTAssertEqual(body["name"] as? String, "Sales")
        XCTAssertNil(body["head_agent_id"], "an unchanged head is not sent")
        await eventually { store.actionFailure != nil }
        XCTAssertEqual(store.actionFailure?.answer.message, "a department named Sales exists")
    }

    func testANewTeamIsCreatedThenItsLeadIsSeated() async throws {
        let store = try Wire17.store()
        FakeServer.serve { request in
            switch (request.httpMethod, request.url?.path) {
            case ("POST", "/api/v1/departments/1/teams"):
                return .init(json: #"{"id":9,"name":"Payments","members":[]}"#)
            case ("PUT", "/api/v1/teams/9/members/4"):
                return .init(json: #"{"id":9,"name":"Payments","members":[{"agent_id":4,"team_role":"team_lead"}]}"#)
            default: return .init(json: "{}")
            }
        }
        store.saveTeam(nil, name: "Payments", department: 1, lead: 4) {}
        let created = try await Wire17.sent("POST", "/api/v1/departments/1/teams")
        XCTAssertEqual(created["name"] as? String, "Payments")
        let seat = try await Wire17.sent("PUT", "/api/v1/teams/9/members/4")
        XCTAssertEqual(seat["team_role"] as? String, "team_lead")
    }

    func testDeletingATeamAndUnseatingAnAgentCallTheServer() async throws {
        let store = try Wire17.store()
        let model = try XCTUnwrap(store.model)
        let team = try XCTUnwrap(model.departments.flatMap(\.teams).first)
        FakeServer.serve { _ in .init(json: #"{"id":1,"name":"t","members":[]}"#) }
        store.unseat(try XCTUnwrap(model.agents[4]), from: team)
        _ = try await Wire17.sent("DELETE", "/api/v1/teams/\(team.id)/members/4")
        store.deleteTeam(team) {}
        _ = try await Wire17.sent("DELETE", "/api/v1/teams/\(team.id)")
    }

    func testAnOlderServerGetsNoStructureWrite() async throws {
        let store = try Wire17.store(minor: 16)
        let team = try XCTUnwrap(store.model?.departments.flatMap(\.teams).first)
        FakeServer.serve { _ in .init(status: 404, json: Wire.refusal("not_found", "no route")) }
        store.saveDepartment(nil, name: "Sales", about: "", head: nil) {}
        store.saveTeam(nil, name: "Pay", department: 1, lead: nil) {}
        store.deleteTeam(team) {}
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(FakeServer.requests.filter { $0.httpMethod != "GET" }.isEmpty)
        XCTAssertNil(store.actionFailure)
    }

    func testADepartmentsStoredHeadWinsOverTheChainOfCommand() throws {
        let model = try XCTUnwrap(Wire17.store().model)
        var department = try XCTUnwrap(model.departments.first)
        department.headAgentID = 5
        XCTAssertEqual(model.head(of: department)?.id, 5)
    }
}
