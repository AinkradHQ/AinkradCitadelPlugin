import AinkradAppKit
import Foundation
import XCTest

@testable import CitadelFeature

/// API minors 10–15 wired, and the audit's functional fixes: blockers, sprint scope, workflow pushes,
/// the Runs screen, sidebar selection and names said once.
@MainActor
final class WireFifteenTests: XCTestCase {
    private func store() throws -> CitadelStore {
        let settings = SettingsStore(documents: MemoryDocs())
        settings.update { $0.server = "https://citadel.example.com" }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_k", company: 1,
            session: FakeServer.session())
        store.model = CompanyFixture.model()
        return store
    }

    private func request(_ method: String, _ path: String) async throws -> [String: Any] {
        await eventually { FakeServer.requests.contains { $0.url?.path == path && $0.httpMethod == method } }
        let request = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == path && $0.httpMethod == method })
        guard let data = request.wireBody, !data.isEmpty else { return [:] }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    nonisolated private static func issue(_ id: Int, sprint: Int? = nil) -> String {
        #"{"id":\#(id),"key":"CIT-\#(id)","number":\#(id),"title":"t","body":"","kind":"task","project_id":1,"state":"todo","labels":[],"priority":false,"rank":1\#(sprint.map { #","sprint_id":\#($0)"# } ?? "")}"#
    }

    // MARK: - Blockers and sprints (minors 12–14)

    func testLinkUnlinkAndBlockOnABlocker() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { request in
            switch request.url?.path {
            case "/api/v1/issues/64/blockers": .init(json: "[\(Self.issue(61))]")
            case "/api/v1/projects/1/sprints": .init(json: "[]")
            case "/api/v1/projects/1/issues": .init(json: "[\(Self.issue(64)),\(Self.issue(61))]")
            default: .init(json: Self.issue(64))
            }
        }
        let issue = try XCTUnwrap(model.issue(64))
        let blocker = try XCTUnwrap(model.issue(61))
        store.linkBlocker(issue, blocker: blocker)
        _ = try await request("PUT", "/api/v1/issues/64/blockers/61")
        await eventually { model.blockers[64]?.map(\.id) == [61] }
        store.unlinkBlocker(issue, blocker: blocker)
        _ = try await request("DELETE", "/api/v1/issues/64/blockers/61")
        store.block(issue, on: blocker)
        let body = try await request("POST", "/api/v1/issues/64/transition")
        XCTAssertEqual(body["kind"] as? String, "block")
        XCTAssertEqual(body["blocker_issue_id"] as? Int, 61, "the block names its blocker and links it in one step")
    }

    func testAnIssueJoinsTheActiveSprintAndAnEmptyPlannedSprintIsDeleted() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { request in
            switch request.url?.path {
            case "/api/v1/projects/1/sprints":
                .init(
                    json:
                        #"[{"id":3,"project_id":1,"name":"CIT Sprint 4","goal":"","state":"active"},{"id":4,"project_id":1,"name":"CIT Sprint 5","goal":"","state":"planned"}]"#
                )
            case "/api/v1/projects/1/issues": .init(json: "[\(Self.issue(64, sprint: 3))]")
            case "/api/v1/issues/64/blockers": .init(json: "[]")
            case "/api/v1/sprints/4":
                .init(json: #"{"id":4,"project_id":1,"name":"CIT Sprint 5","goal":"","state":"planned"}"#)
            default: .init(json: Self.issue(64, sprint: 3))
            }
        }
        let issue = try XCTUnwrap(model.issue(64))
        store.setSprint(issue, to: ProjectSprintInfo(id: 3, name: "CIT Sprint 4", state: "active"))
        let body = try await request("POST", "/api/v1/issues/64/sprint")
        XCTAssertEqual(body["sprint_id"] as? Int, 3, "API minor 12: an active sprint takes the issue (a scope change)")
        await eventually { model.issue(64)?.sprintID == 3 && model.projectSprints[1]?.count == 2 }
        store.setSprint(issue, to: nil)
        await eventually {
            FakeServer.requests.filter { $0.url?.path == "/api/v1/issues/64/sprint" }.count == 2
        }
        store.deleteSprint(ProjectSprintInfo(id: 4, name: "CIT Sprint 5", state: "planned"), of: issue)
        _ = try await request("DELETE", "/api/v1/sprints/4")
        XCTAssertNil(store.actionFailure)
    }

    func testARefusedScopeChangeSaysWhy() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { _ in .init(status: 409, json: Wire.refusal("conflict", "the issue needs points")) }
        store.setSprint(try XCTUnwrap(model.issue(64)), to: ProjectSprintInfo(id: 3, name: "S4", state: "active"))
        await eventually { store.actionFailure != nil }
        XCTAssertEqual(store.actionFailure?.answer.message, "the issue needs points")
        XCTAssertEqual(store.actionFailure?.title, "Couldn't add CIT-64 to S4")
    }

    // MARK: - Workflow pushes (minor 15)

    func testAWorkflowPushReadsAsAPushByHandAndUnknownKindsStillShow() {
        let model = CompanyFixture.model()
        let push = ApprovalInfo(
            id: 70, kind: "workflow_push", agentID: nil, issueID: 64, requestedBy: 3, expiresAt: nil,
            fields: [
                "branch": "cit-64-spec", "sha": "abcdef1234567", "repo": "AinkradHQ/citadel",
                "files": ".github/workflows/ci.yml", "rejection": "refusing to allow a token without workflow scope",
            ])
        let summary = model.summary(push)
        XCTAssertEqual(summary.typeLabel, "Workflow push")
        XCTAssertEqual(summary.title, "Push cit-64-spec by hand")
        XCTAssertTrue(summary.subtitle.contains("AinkradHQ/citadel @ abcdef1"))
        XCTAssertTrue(ApprovalFilter.merge.matches(push))
        let future = ApprovalInfo(
            id: 71, kind: "teleport", agentID: nil, issueID: nil, requestedBy: 3, expiresAt: nil,
            fields: ["summary": "Beam it up"])
        model.approvals = [future, push]
        XCTAssertEqual(model.inbox(.all).map(\.id), [70, 71], "a kind this build doesn't know still lists")
        XCTAssertEqual(model.summary(future).title, "Beam it up")
    }

    func testAWakeIsNotedOnItsIssueOnce() {
        let model = CompanyFixture.model()
        let now = Date()
        model.woke(WakeNote(agentID: 3, source: "comment", reason: "your message", at: now), on: 64)
        model.woke(WakeNote(agentID: 3, source: "comment", reason: "Cut it", at: now.addingTimeInterval(1)), on: 64)
        model.woke(WakeNote(agentID: 4, source: "blocker_closed", reason: "CIT-61 done", at: now), on: 64)
        XCTAssertEqual(model.wakes[64]?.map(\.agentID), [3, 4], "your post and its stream event are one wake")
    }

    // MARK: - Runs screen

    func testTheRunsScreenListsTheCompanysRunsNewestFirst() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/companies/1/runs" else { return .init(json: Self.issue(64)) }
            return .init(
                json:
                    #"{"items":[{"id":500,"agent_id":3,"state":"running","harness":"codex","usage":{"input_tokens":1,"output_tokens":1,"cache_tokens":0},"queued_at":"2026-10-23T09:50:00.000Z","diff_repos":[]},{"id":499,"agent_id":3,"issue_id":64,"state":"succeeded","harness":"codex","usage":{"input_tokens":1,"output_tokens":1,"cache_tokens":0},"queued_at":"2026-10-23T09:40:00.000Z","diff_repos":[]}]}"#
            )
        }
        store.loadRunsPage()
        await eventually { model.companyRuns?.map(\.id) == [500, 499] }
        let list = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == "/api/v1/companies/1/runs" })
        XCTAssertEqual(list.query["limit"], "100")
        let issueless = try XCTUnwrap(model.companyRuns?.first)
        XCTAssertTrue(model.runTitle(issueless).hasSuffix("run #500, no issue"), "never a bare \"Run 500\"")
    }

    // MARK: - Selection and wording

    func testTheSidebarFollowsTheOpenPage() {
        XCTAssertEqual(Detail.run(4).screen, .runs)
        XCTAssertEqual(Detail.agent(4).screen, .org)
    }

    func testNamesAreSaidOnce() {
        XCTAssertEqual(Wording.count(1, "department"), "1 department")
        XCTAssertEqual(Wording.count(2, "department"), "2 departments")
        XCTAssertEqual(Wording.parenthesized("Product Owner", "Product Owner"), "Product Owner")
        XCTAssertEqual(Wording.parenthesized("Mira", "PO"), "Mira (PO)")
        XCTAssertEqual(Wording.name("CEO", "CEO"), "CEO")
        XCTAssertEqual(Wording.sprint(key: "WRK", name: "WRK Sprint 1"), "WRK Sprint 1")
        XCTAssertEqual(Wording.sprint(key: "WRK", name: "Sprint 1"), "WRK Sprint 1")
        XCTAssertEqual(Wording.sprint(key: "CIT", name: "S4"), "Sprint CIT S4")
        let model = CompanyFixture.model()
        let commit = ApprovalInfo(
            id: 1, kind: "sprint_commit", agentID: nil, issueID: nil, requestedBy: 3, expiresAt: nil,
            fields: ["name": "WRK Sprint 1"], lists: ["issues": [["key": "WRK-1"]]])
        XCTAssertEqual(model.summary(commit).title, "Commit WRK Sprint 1")
    }

    func testProgressIsNeverTheBudgetsRed() {
        XCTAssertEqual(AinkradChartTone.progress(5, of: 5), .success, "done is done, not over a limit")
        XCTAssertEqual(AinkradChartTone.progress(2, of: 5), .accentSecondary)
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
