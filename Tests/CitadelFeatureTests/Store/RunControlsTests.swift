import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// Screens 02–07's controls: each sends its request, a refusal becomes the 11 G failure, the open questions come
/// from the company list with the threads' answered receipts, and the run rail reads each repo's diff.
@MainActor
final class RunControlsTests: XCTestCase {
    private func store() throws -> CitadelStore {
        let settings = SettingsStore(documents: MemoryDocs())
        settings.update { $0.server = "https://citadel.example.com" }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_k", company: 1,
            session: FakeServer.session())
        store.companies = [
            Components.Schemas.Company(accountIds: [], id: 1, kind: .init(value1: .own), name: "Ainkrad")
        ]
        store.settings.update { $0.companyID = 1 }
        store.model = CompanyFixture.model()
        return store
    }

    private func body(_ request: URLRequest) -> [String: Any]? {
        guard let stream = request.httpBodyStream else {
            return request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) as? [String: Any] }
        }
        stream.open()
        defer { stream.close() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1024)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            data.append(buffer, count: n)
        }
        return try? JSONSerialization.jsonObject(with: data) as? [String: Any]
    }

    private func sent(_ path: String) async -> URLRequest? {
        await eventually { FakeServer.requests.contains { $0.url?.path == path } }
        return FakeServer.requests.first { $0.url?.path == path }
    }

    func testEachControlPostsToItsEndpoint() async throws {
        FakeServer.serve { _ in .init(json: "{}") }
        let store = try store()
        let kestrel = try XCTUnwrap(store.model?.agents[4])
        store.setPaused(kestrel, true)
        store.setPaused(kestrel, false)
        store.setCompanyPaused(true)
        store.setCompanyPaused(false)
        store.stop(run: 418)
        for path in [
            "/api/v1/agents/4/pause", "/api/v1/agents/4/resume", "/api/v1/companies/1/pause",
            "/api/v1/companies/1/resume", "/api/v1/runs/418/stop",
        ] {
            let request = await sent(path)
            XCTAssertEqual(request?.httpMethod, "POST", path)
        }
    }

    func testAMessageReachesTheRunAndClearsTheDraftOnlyOnceTaken() async throws {
        FakeServer.serve { _ in .init(json: #"{"delivered_as":"run","message_id":3}"#) }
        let store = try store()
        var cleared = false
        store.message(run: 418, "  carry on with the sandbox key \n") { cleared = true }
        let sentRequest = await sent("/api/v1/runs/418/messages")
        let request = try XCTUnwrap(sentRequest)
        XCTAssertEqual(body(request)?["body"] as? String, "carry on with the sandbox key")
        await eventually { cleared }
        XCTAssertTrue(cleared)
        store.message(run: 418, "   ") { XCTFail("an empty message is never sent") }
    }

    func testARefusalBecomesTheActionFailureAndNothingElse() async throws {
        FakeServer.serve { _ in
            .init(status: 409, json: Wire.refusal("conflict", "The run already ended."))
        }
        let store = try store()
        store.stop(run: 418)
        await eventually { store.actionFailure != nil }
        let failure = try XCTUnwrap(store.actionFailure)
        XCTAssertEqual(failure.title, "Couldn't stop run #418")
        XCTAssertEqual(
            failure.answer,
            ServerAnswer(status: 409, code: "conflict", message: "The run already ended.", errorID: "err_01JTEST")
        )
        XCTAssertEqual(failure.message, "The server answered 409: The run already ended. It keeps running.")
    }

    func testAllowForIssueApprovesWithTheReplyAndClearsTheCard() async throws {
        FakeServer.serve { _ in
            .init(
                json:
                    #"{"id":23,"company_id":1,"kind":"permission_escalation","requested_by":4,"status":"approved","payload":{}}"#
            )
        }
        let store = try store()
        let model = try XCTUnwrap(store.model)
        let approval = ApprovalInfo(
            id: 23, kind: "permission_escalation", agentID: 4, issueID: 42, requestedBy: 4, expiresAt: nil,
            fields: ["run": "418"])
        model.approvals = [approval]
        store.allowForIssue(approval, reply: "fine for this issue")
        let sentRequest = await sent("/api/v1/approvals/23/allow-for-issue")
        let request = try XCTUnwrap(sentRequest)
        XCTAssertEqual(body(request)?["reply"] as? String, "fine for this issue")
        await eventually { model.approvals.isEmpty }
        XCTAssertTrue(model.approvals.isEmpty)
    }

    func testOpenQuestionsComeFromTheCompanyListAndAnsweredOnesFromTheThreads() async throws {
        func question(_ id: Int, _ issue: Int, _ state: String, requirement: Int? = nil) -> String {
            let req = requirement.map { #","requirement_id":\#($0)"# } ?? ""
            return
                #"{"id":\#(id),"asked_by_agent_id":4,"issue_id":\#(issue),"issue_key":"CIT-\#(issue)","question":"q\#(id)","options":[],"state":"\#(state)","created_at":"2026-10-23T09:0\#(id):00.000Z"\#(req)}"#
        }
        // Built here: the fake server answers off the main actor.
        let open = "[\(question(2, 62, "open")), \(question(5, 70, "open"))]"
        let thread =
            #"{"requirement_id":12,"items":[{"kind":"question","question":\#(question(1, 58, "answered", requirement: 12))},{"kind":"question","question":\#(question(2, 62, "open", requirement: 12))}]}"#
        FakeServer.serve { request in
            switch request.url?.path {
            case "/api/v1/companies/1/questions": .init(json: open)
            case "/api/v1/requirements/12/thread": .init(json: thread)
            default: .init(status: 404, json: "{}")
            }
        }
        let store = try store()
        let model = try XCTUnwrap(store.model)
        model.requirements = [RequirementInfo(id: 12, key: "R-12", title: "Phone alerts", state: "in_progress")]
        await store.loadQuestions(model, server: try XCTUnwrap(store.server))
        XCTAssertEqual(model.questions.map(\.id), [1, 2, 5], "answered receipt, then the open ones, oldest first")
        XCTAssertEqual(model.questions.filter(\.isOpen).map(\.issueID), [62, 70], "CIT-70 is outside any requirement")
    }

    func testTheRunCarriesEachReposDiff() throws {
        let json =
            #"{"id":418,"agent_id":4,"state":"running","harness":"codex","usage":{"input_tokens":1,"output_tokens":1,"cache_tokens":0},"queued_at":"2026-10-23T09:50:00.000Z","diff_repos":[{"repo":"citadel","files":3,"insertions":38,"deletions":6},{"repo":"ainkrad-citadel-plugin","files":1,"insertions":12,"deletions":0}]}"#
        let run = RunInfo(try EventFrame.decoder.decode(Schemas.Run.self, from: Data(json.utf8)))
        XCTAssertEqual(
            run.diffRepos,
            [
                RepoDiffInfo(repo: "citadel", files: 3, insertions: 38, deletions: 6),
                RepoDiffInfo(repo: "ainkrad-citadel-plugin", files: 1, insertions: 12, deletions: 0),
            ])
    }
}
