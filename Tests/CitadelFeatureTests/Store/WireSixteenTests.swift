import AinkradAppKit
import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 16 wired: an issue's PRs read from the server, the paged audit log, and project knowledge review.
@MainActor
final class WireSixteenTests: XCTestCase {
    private func store() throws -> CitadelStore {
        let settings = SettingsStore(documents: MemoryDocs())
        settings.update { $0.server = "https://citadel.example.com" }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_FAKE_fixture", company: 1,
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

    // MARK: - Issue PRs

    nonisolated private static let prs =
        #"[{"repo_id":1,"repo":"citadel","state":"open","title":"t","head":"cit-64","base":"development","checks":"success","checks_note":"1 of 2 read","number":42,"url":"https://github.com/x/citadel/pull/42","updated_at":"2026-10-23T10:00:00.000Z"},{"repo_id":2,"repo":"app","state":"teleported","title":"t","head":"cit-64","base":"development","checks":"none","last_error":"push rejected: protected branch","push_held":"workflow files changed","unpushed_at":"2026-10-23T09:00:00.000Z","updated_at":"2026-10-23T10:00:00.000Z"}]"#

    func testAnIssuesPRsAreReadFromTheServerAndAgainOnAPREvent() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { request in
            request.url?.path == "/api/v1/issues/64/prs" ? .init(json: Self.prs) : .init(json: "[]")
        }
        await store.refreshIssueWork(64, project: 1, model: model, server: try XCTUnwrap(store.server))
        let prs = try XCTUnwrap(model.issuePRs[64])
        XCTAssertEqual(prs.map(\.repo), ["citadel", "app"])
        XCTAssertEqual(IssuePRList.line(prs[0]), "#42 · cit-64 → development · checks success")
        XCTAssertEqual(prs[0].checksNote, "1 of 2 read")
        XCTAssertEqual(prs[1].state, "teleported", "a state this build doesn't know is kept as its word")
        XCTAssertEqual(IssuePRList.status(prs[1].state), .neutral)
        XCTAssertEqual(prs[1].lastError, "push rejected: protected branch")
        XCTAssertEqual(prs[1].pushHeld, "workflow files changed")
        XCTAssertNotNil(prs[1].unpushedAt)
        let reloads = model.audited(
            action: "pr.push_failed", entity: 64, kind: "issue", run: nil, details: [:], at: Date())
        XCTAssertTrue(reloads.contains(.pullRequests(64)), "a pr event reads an opened issue's PRs again")
        XCTAssertFalse(
            model.audited(action: "pr.opened", entity: 65, kind: "issue", run: nil, details: [:], at: Date())
                .contains(.pullRequests(65)), "an issue never opened is not read")
    }

    // MARK: - Audit log

    func testTheAuditLogPagesAndFiltersByKind() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        let row = { (seq: Int, action: String) in
            #"{"seq":\#(seq),"at":"2026-10-23T10:00:00.000Z","action":"\#(action)","actor":{"kind":"agent","agent_id":3},"entity_kind":"issue","entity_id":64,"details":{"title":"x"}}"#
        }
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/audit" else { return .init(status: 404, json: Wire.refusal("x", "x")) }
            if request.query["before"] == "8" { return .init(json: #"{"items":[\#(row(7, "issue.done"))]}"#) }
            return .init(
                json: #"{"items":[\#(row(9, "knowledge.accepted")),\#(row(8, "issue.todo"))],"next_before":8}"#)
        }
        store.loadAuditLog()
        await eventually { model.limitsPage.auditLog?.count == 2 }
        XCTAssertEqual(model.limitsPage.auditNext, 8)
        XCTAssertEqual(model.limitsPage.auditLog?.first?.actor, "agent:3")
        XCTAssertEqual(model.limitsPage.auditLog?.first?.entity, "issue 64")
        store.loadMoreAudit()
        await eventually { model.limitsPage.auditLog?.count == 3 }
        XCTAssertEqual(model.limitsPage.auditLog?.map(\.seq), [9, 8, 7])
        XCTAssertNil(model.limitsPage.auditNext, "the last page has no next")
        model.limitsPage.auditKind = "knowledge."
        store.loadAuditLog()
        await eventually { FakeServer.requests.contains { $0.query["kind"] == "knowledge." } }
        await eventually { model.limitsPage.auditLog?.count == 2 }
    }

    // MARK: - Knowledge

    nonisolated private static let knowledge =
        #"[{"id":5,"project_id":1,"kind":"decision","title":"Use sqlite","body":"WAL mode","status":"accepted","created_at":"2026-10-23T10:00:00.000Z","updated_at":"2026-10-23T10:00:00.000Z","body_truncated":false,"superseded_by":null},{"id":6,"project_id":1,"kind":"omen","title":"Lint","body":"cargo clippy","status":"proposed","target":"profile.lint","proposed_by_agent_id":3,"rationale":"CI failed twice","created_at":"2026-10-23T10:00:00.000Z","updated_at":"2026-10-23T10:00:00.000Z","body_truncated":true}]"#

    func testKnowledgeIsListedAndDecided() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { request in
            switch request.url?.path {
            case "/api/v1/projects/1/knowledge": return .init(json: Self.knowledge)
            case let path? where path.hasPrefix("/api/v1/knowledge/"):
                return .init(
                    json:
                        #"{"id":6,"project_id":1,"kind":"state","title":"Lint","body":"b","status":"accepted","created_at":"2026-10-23T10:00:00.000Z","updated_at":"2026-10-23T10:00:00.000Z","body_truncated":false}"#
                )
            default: return .init(status: 404, json: Wire.refusal("not_found", "no"))
            }
        }
        await store.reloadKnowledge(1, model: model, server: try XCTUnwrap(store.server))
        let entries = try XCTUnwrap(model.projectsPage.knowledge[1])
        XCTAssertEqual(entries.map(\.status), ["accepted", "proposed"])
        XCTAssertEqual(entries[1].kind, "omen", "a kind this build doesn't know is kept as its word")
        XCTAssertEqual(entries[1].target, "profile.lint")
        XCTAssertEqual(entries[1].proposedBy, 3)
        XCTAssertTrue(entries[1].bodyTruncated)

        store.decide(entries[1], project: 1, accept: false, reason: " covered by CI ")
        let reject = try await request("POST", "/api/v1/knowledge/6/reject")
        XCTAssertEqual(reject["reason"] as? String, "covered by CI")
        store.decide(entries[1], project: 1, accept: true)
        _ = try await request("POST", "/api/v1/knowledge/6/accept")
        store.retire(entries[0], project: 1, reason: "moved to postgres")
        let retire = try await request("POST", "/api/v1/knowledge/5/retire")
        XCTAssertEqual(retire["reason"] as? String, "moved to postgres")
        store.supersede(entries[0], project: 1, body: "WAL mode, 5s busy timeout")
        let supersede = try await request("POST", "/api/v1/knowledge/5/supersede")
        XCTAssertEqual(supersede["body"] as? String, "WAL mode, 5s busy timeout")
        XCTAssertEqual(
            model.audited(
                action: "knowledge.accepted", entity: 6, kind: "knowledge_entry", run: nil, details: [:],
                at: Date()), [.knowledge])
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
