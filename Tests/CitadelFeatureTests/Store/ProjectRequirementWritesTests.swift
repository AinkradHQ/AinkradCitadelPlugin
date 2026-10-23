import Foundation
import XCTest

@testable import CitadelFeature

/// Screens 14 and 12's writes from API minor 7: a new project, a decided proposal, the profile history, and a
/// requirement renamed, cancelled or given a file.
extension ProjectLimitsTests {
    nonisolated private static let profile =
        #"{"project_id":1,"profile":{"stack":"Rust"},"sprint_approval":"owner","permission_mode":"ask","injected_bytes":10,"budget_bytes":4096,"dropped":[],"proposals":[]}"#
    nonisolated private static let requirement =
        #"{"id":12,"company_id":1,"key":"R-12","number":12,"title":"Phone alerts","body":"","requested_by_user_id":1,"state":"in_progress","plan_version":1,"created_at":"2026-10-22T09:00:00.000Z"}"#

    func testANewProjectJoinsTheListSelectedAndATakenKeyStaysInTheSheet() async throws {
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/companies/1/projects" else { return .init(status: 404) }
            return .init(
                json: #"{"id":5,"company_id":1,"name":"Ops","key":"OPS","mode":"kanban","sprint_approval":"owner"}"#)
        }
        let (store, model) = try connectedStore()
        var refused: ActionFailure?? = nil
        store.createProject(name: " Ops ", key: "ops", mode: "kanban") { refused = $0 }
        await eventually { refused != nil }
        XCTAssertNil(refused ?? nil)
        XCTAssertEqual(model.projects.last, ProjectInfo(id: 5, key: "OPS", name: "Ops", teamID: nil, mode: "kanban"))
        XCTAssertEqual(model.projectsPage.selected, 5)
        let sent = body(try XCTUnwrap(FakeServer.requests.first))
        XCTAssertEqual(sent["key"] as? String, "OPS", "the key goes upper-cased")
        XCTAssertEqual(sent["name"] as? String, "Ops")
        XCTAssertEqual(sent["mode"] as? String, "kanban")

        FakeServer.serve { _ in .init(status: 409, json: Wire.refusal("conflict", "the key OPS is taken")) }
        refused = nil
        store.createProject(name: "Ops", key: "OPS", mode: "scrum") { refused = $0 }
        await eventually { refused != nil }
        XCTAssertEqual(refused??.answer.errorID, "err_01JTEST")
        XCTAssertEqual(refused??.answer.message, "the key OPS is taken")
        XCTAssertTrue(NewProjectSheet.isKey("AMC2"))
        XCTAssertFalse(NewProjectSheet.isKey("2AMC"))
        XCTAssertFalse(NewProjectSheet.isKey("ABCDEFGHIJK"))
    }

    func testRejectingAProposalSendsTheReasonAndTheProfileComesBackWithoutIt() async throws {
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/projects/1/profile/proposals/2/decision" else {
                return .init(status: 404)
            }
            return .init(json: Self.profile)
        }
        let (store, model) = try connectedStore()
        CompanyFixture.projectsPage(model)
        let proposal = try XCTUnwrap(model.projectsPage.profiles[1]?.proposals.last)
        store.decide(proposal, project: 1, accept: false, reason: "  covered by CI  ")
        await eventually { model.projectsPage.profiles[1]?.proposals.isEmpty == true }
        let sent = body(try XCTUnwrap(FakeServer.requests.first))
        XCTAssertEqual(sent["accept"] as? Bool, false)
        XCTAssertEqual(sent["reason"] as? String, "covered by CI")

        FakeServer.serve { _ in .init(status: 403, json: Wire.refusal("forbidden", "a person decides proposals")) }
        store.decide(proposal, project: 1, accept: true, reason: "")
        await eventually { store.actionFailure != nil }
        XCTAssertEqual(store.actionFailure?.title, "Couldn't accept Definition of done")
        XCTAssertEqual(store.actionFailure?.answer.errorID, "err_01JTEST")
    }

    func testTheProfileHistoryNamesWhoDidWhatAndWhy() async throws {
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/projects/1/profile/history" else { return .init(status: 404) }
            return .init(
                json: """
                    [{"seq":9,"at":"2026-10-22T10:00:00.000Z","actor":{"kind":"user","user_id":1},"action":"knowledge.rejected","details":{"title":"Lint command","reason":"covered by CI"}},
                     {"seq":8,"at":"2026-10-22T09:00:00.000Z","actor":{"kind":"agent","agent_id":7},"action":"knowledge.proposed","details":{"title":"Lint command","profile_field":"conventions","rationale":"CI failed twice"}},
                     {"seq":7,"at":"2026-10-21T09:00:00.000Z","actor":{"kind":"user","user_id":1},"action":"project.profile_set","details":{"fields":["merge_method","merged_by"]}}]
                    """)
        }
        let (store, model) = try connectedStore()
        store.loadProfileHistory(1)
        await eventually { model.projectsPage.history[1] != nil }
        let history = try XCTUnwrap(model.projectsPage.history[1])
        XCTAssertEqual(
            history.map(\.line), ["rejected Lint command", "proposed Lint command", "changed merge method, merged by"])
        XCTAssertEqual(history.map(\.why), ["covered by CI", "CI failed twice", nil])
        XCTAssertEqual(history.map(\.agentID), [nil, 7, nil])
        XCTAssertEqual(history.map(\.byPerson), [true, false, true])
    }

    func testRenameCancelAndAttachGoToTheRequirementAndARefusalIsTheBanner() async throws {
        FakeServer.serve { request in
            switch request.url?.path {
            case "/api/v1/requirements/12", "/api/v1/requirements/12/cancel": .init(json: Self.requirement)
            case "/api/v1/requirements/12/attachments/notes.txt":
                .init(
                    json:
                        #"{"id":3,"company_id":1,"name":"notes.txt","kind":"file","mime":"text/plain","size":5,"sha256":"x","redactions":0,"unscanned":false,"preview":"","created_at":"2026-10-22T09:00:00.000Z"}"#
                )
            default: .init(status: 404)
            }
        }
        let (store, model) = try connectedStore()
        let requirement = try XCTUnwrap(model.requirements.first { $0.id == 12 })
        store.rename(requirement: requirement, to: "  Phone alerts  ")
        await eventually { model.requirements.first { $0.id == 12 }?.title == "Phone alerts" }
        let rename = try XCTUnwrap(FakeServer.requests.first { $0.httpMethod == "PUT" })
        XCTAssertEqual(body(rename)["title"] as? String, "Phone alerts")

        store.cancel(requirement: requirement, reason: "")
        await eventually { model.requirements.first { $0.id == 12 }?.state == "cancelled" }
        let cancel = try XCTUnwrap(FakeServer.requests.first { $0.url?.path.hasSuffix("/cancel") == true })
        XCTAssertNil(body(cancel)["reason"] as? String, "an empty reason is left out")

        let file = FileManager.default.temporaryDirectory.appendingPathComponent("notes.txt")
        try Data("hello".utf8).write(to: file)
        store.attach(file, requirement: requirement)
        await eventually { FakeServer.requests.contains { $0.url?.path.contains("/attachments/") == true } }
        let upload = try XCTUnwrap(FakeServer.requests.first { $0.url?.path.contains("/attachments/") == true })
        XCTAssertEqual(upload.httpMethod, "POST")
        XCTAssertEqual(upload.value(forHTTPHeaderField: "Content-Type"), "application/octet-stream")

        FakeServer.serve { _ in .init(status: 409, json: Wire.refusal("conflict", "a run works on CIT-62")) }
        store.cancel(requirement: requirement, reason: "dropped")
        await eventually { store.actionFailure != nil }
        XCTAssertEqual(store.actionFailure?.title, "Couldn't cancel R-12")
        XCTAssertEqual(store.actionFailure?.answer.line, "409 conflict: a run works on CIT-62 · err_01JTEST")
    }
}
