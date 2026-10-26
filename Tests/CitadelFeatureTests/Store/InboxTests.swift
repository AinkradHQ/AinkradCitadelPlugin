import AinkradAppKit
import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// Screens 06 and 07: the approval payload mapping, the inbox's order and filters, the agent threads built from
/// runs, comments and questions, the sidebar counts — and the actions they send to the server.
@MainActor
final class InboxTests: XCTestCase {
    private func decode<T: Decodable>(_ type: T.Type, _ json: String) throws -> T {
        try EventFrame.decoder.decode(T.self, from: Data(json.utf8))
    }

    // MARK: - Mapping

    func testAnApprovalKeepsItsPayloadListsAndWordLists() throws {
        let approval = ApprovalInfo(
            try decode(
                Schemas.Approval.self,
                #"{"id":21,"company_id":1,"kind":"sprint_commit","status":"pending","requested_by":3,"sprint_id":5,"reply":null,"payload":{"name":"S5","points":31,"capacity":34,"issues":[{"id":62,"key":"CIT-62","title":"APNs push","points":8}],"runner_tags":["linux","macos"]}}"#
            ))
        XCTAssertEqual(approval.status, "pending")
        XCTAssertEqual(approval.sprintID, 5)
        XCTAssertEqual(approval.fields["points"], "31")
        XCTAssertEqual(approval.fields["runner_tags"], "linux macos")
        XCTAssertEqual(approval.lists["issues"]?.first?["key"], "CIT-62")
        XCTAssertEqual(approval.lists["issues"]?.first?["points"], "8")
    }

    func testAnIssueCarriesItsStateAndNextActorAndACommentItsAuthor() throws {
        let issue = IssueInfo(
            try decode(
                Schemas.Issue.self,
                #"{"id":8,"key":"MKT-8","number":8,"labels":[],"priority":false,"title":"Launch post","body":"","kind":"task","project_id":3,"rank":1,"state":"in_progress","owner":{"kind":"human","user_id":1},"next_actor":{"kind":"human","user_id":1}}"#
            ))
        XCTAssertEqual(issue.state, "in_progress")
        XCTAssertEqual(issue.nextActor, .human)
        let agent = CommentInfo(
            try decode(
                Schemas.Comment.self,
                #"{"id":2,"issue_id":8,"author":{"kind":"agent","agent_id":15},"body":"hi","run_id":405}"#))
        XCTAssertEqual(agent.agentID, 15)
        XCTAssertEqual(agent.runID, 405)
        let you = CommentInfo(
            try decode(
                Schemas.Comment.self, #"{"id":3,"issue_id":8,"author":{"kind":"human","user_id":1},"body":"ok"}"#))
        XCTAssertNil(you.agentID)
    }

    // MARK: - The inbox

    func testTheInboxPutsWhatBlocksARunFirstAndFiltersByKind() {
        let model = CompanyFixture.model()
        CompanyFixture.inboxPage(model)
        XCTAssertEqual(model.inbox(.all).map(\.kind).prefix(2).sorted(), ["budget_overrun", "permission_escalation"])
        XCTAssertEqual(model.inbox(.all).last?.kind, "hire_agent")
        XCTAssertEqual(model.inbox(.merge).map(\.id), [22])
        XCTAssertEqual(model.inbox(.sprint).map(\.id), [21])
        XCTAssertEqual(model.summary(model.approvals[0]).title, "Commit sprint CIT S5")
        XCTAssertEqual(model.summary(model.approvals[1]).typeLabel, "PR merge · 2 PRs")
        XCTAssertEqual(model.summary(model.approvals[3]).subtitle, "Quill · 200.4k of 200k tokens")
    }

    func testADecisionMovesTheApprovalToAnsweredWithItsReply() {
        let model = CompanyFixture.model()
        CompanyFixture.inboxPage(model)
        let hire = model.approvals[4]
        model.answer(hire, approved: false, reply: "Not this sprint")
        XCTAssertFalse(model.approvals.contains { $0.id == hire.id })
        XCTAssertEqual(model.answeredApprovals.first?.status, "rejected")
        XCTAssertEqual(model.answeredApprovals.first?.reply, "Not this sprint")
    }

    func testANewCapReadsAsTokens() {
        XCTAssertEqual(ApprovalDetail.tokens("240k"), 240_000)
        XCTAssertEqual(ApprovalDetail.tokens("1.2M tokens"), 1_200_000)
        XCTAssertEqual(ApprovalDetail.tokens("300,000"), 300_000)
        XCTAssertNil(ApprovalDetail.tokens("lots"))
        XCTAssertNil(ApprovalDetail.tokens("0"))
    }

    // MARK: - Threads

    func testThreadsWaitingOnYouComeFirstAndADeadRunIsMarked() {
        let model = CompanyFixture.model()
        CompanyFixture.threadsPage(model)
        let threads = model.threads()
        XCTAssertEqual(threads.first?.key, ThreadKey(agentID: 15, issueID: 8))
        XCTAssertEqual(threads.first?.waitingOnYou, true)
        XCTAssertEqual(threads.first?.requirementKey, "R-10")
        XCTAssertTrue(threads.first?.lastLine.hasPrefix("Quill: Rewrote the intro") ?? false)
        let lost = threads.first { $0.key == ThreadKey(agentID: 8, issueID: 49) }
        XCTAssertEqual(lost?.died, true)
        XCTAssertEqual(lost?.lastLine, "run ended runner lost")
    }

    func testAConversationPlacesEachRunBeforeTheCommentItWroteAndTheQuestionLast() {
        let model = CompanyFixture.model()
        CompanyFixture.threadsPage(model)
        let ids = model.conversation(ThreadKey(agentID: 15, issueID: 8)).map(\.id)
        XCTAssertEqual(ids, ["c1", "r405", "c2", "r419", "r427", "q3"])
        XCTAssertEqual(model.openQuestion(ThreadKey(agentID: 15, issueID: 8))?.id, 3)
        XCTAssertEqual(model.nextActorWord(model.issues[8]!), "you")
    }

    func testPostingAnswersTheOpenQuestionAndAppendsOnce() {
        let model = CompanyFixture.model()
        CompanyFixture.threadsPage(model)
        let comment = CommentInfo(id: 9, issueID: 8, agentID: nil, body: "Cut it", runID: nil)
        model.posted(comment)
        model.posted(comment)
        XCTAssertEqual(model.comments[8]?.filter { $0.id == 9 }.count, 1)
        XCTAssertNil(model.openQuestion(ThreadKey(agentID: 15, issueID: 8)))
    }

    func testCommentAndQuestionEventsNameWhatToReadAgain() {
        let model = CompanyFixture.model()
        CompanyFixture.threadsPage(model)
        let at = Date()
        XCTAssertEqual(
            model.audited(action: "issue.commented", entity: 8, kind: "issue", run: nil, details: [:], at: at),
            [.stuck, .issueFresh(8), .comments(8)])
        XCTAssertEqual(
            model.audited(action: "issue.commented", entity: 77, kind: "issue", run: nil, details: [:], at: at),
            [.stuck, .issue(77)], "an unloaded thread is not read")
        XCTAssertEqual(
            model.audited(action: "question.asked", entity: 3, kind: nil, run: nil, details: [:], at: at),
            [.questions])
    }

    // MARK: - Sidebar

    func testTheSidebarCountsWhatAsksForYouAsBadges() {
        let model = CompanyFixture.model()
        CompanyFixture.threadsPage(model)
        model.runnersOnline = 2
        XCTAssertEqual(model.navCount(.approvals), AinkradNavCount("3", tone: .warning))
        XCTAssertEqual(model.navCount(.stuck), AinkradNavCount("2", tone: .danger))
        XCTAssertEqual(model.navCount(.org), AinkradNavCount("18"))
        XCTAssertEqual(model.navCount(.threads), AinkradNavCount("1"))
        XCTAssertEqual(model.navCount(.accounts), AinkradNavCount("2", tone: .warning))
        XCTAssertEqual(model.navCount(.runners), AinkradNavCount("2/3"))
        XCTAssertNil(model.navCount(.cost))
    }

    func testTheArtifactsRowCountsLoadedArtifactsAndHidesWhenNone() {
        let model = CompanyFixture.model()
        XCTAssertNil(model.navCount(.artifacts))
        CompanyFixture.artifactsPage(model)
        XCTAssertFalse(model.artifactsPage.items.isEmpty)
        XCTAssertEqual(model.navCount(.artifacts), AinkradNavCount("\(model.artifactsPage.items.count)"))
    }

    func testARunsCapIsTheAgentsOverrideElseTheCompanys() throws {
        let model = CompanyFixture.model()
        let run = try XCTUnwrap(model.runs[418])
        XCTAssertEqual(model.cap(of: run), 200_000)
        model.limits["run.token_cap.agent.\(run.agentID)"] = LimitSetting(value: 50_000, source: nil)
        XCTAssertEqual(model.cap(of: run), 50_000)
    }

    func testTheLastDecisionLineCarriesItsAgeWhenKnown() {
        let model = CompanyFixture.model()
        let now = Date()
        var approval = ApprovalInfo(
            id: 1, kind: "sprint_commit", agentID: nil, issueID: nil, requestedBy: 3, expiresAt: nil, fields: [:])
        XCTAssertFalse(model.lastDecisionLine(approval, now: now).contains("·"))
        approval.decidedAt = now.addingTimeInterval(-240)
        XCTAssertTrue(model.lastDecisionLine(approval, now: now).hasSuffix(" · 4m ago"))
    }

    // MARK: - Actions

    private func connectedStore() throws -> (CitadelStore, CompanyModel) {
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
        return (store, model)
    }

    private func body(_ request: URLRequest) -> [String: Any] {
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            var bytes = Data()
            var buffer = [UInt8](repeating: 0, count: 4096)
            while stream.hasBytesAvailable {
                let n = stream.read(&buffer, maxLength: buffer.count)
                if n <= 0 { break }
                bytes.append(buffer, count: n)
            }
            stream.close()
            data = bytes
        }
        return (data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
    }

    func testADecisionCarriesTheReplyAndMovesToAnswered() async throws {
        FakeServer.serve { _ in
            .init(
                json:
                    #"{"id":25,"company_id":1,"kind":"hire_agent","status":"rejected","requested_by":14,"payload":{}}"#)
        }
        let (store, model) = try connectedStore()
        CompanyFixture.inboxPage(model)
        store.decide(model.approvals[4], approve: false, reply: "  Not this sprint ")
        await eventually { model.answeredApprovals.first?.id == 25 }
        let request = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == "/api/v1/approvals/25/decision" })
        let sent = body(request)
        XCTAssertEqual(sent["approve"] as? Bool, false)
        XCTAssertEqual(sent["reply"] as? String, "  Not this sprint ")
    }

    func testReplyOnlyAndAThreadMessageAreCommentsOnTheIssue() async throws {
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/issues/8/comments" else { return .init(status: 404) }
            return .init(
                json:
                    #"{"comment":{"id":31,"issue_id":8,"author":{"kind":"human","user_id":1},"body":"Cut it"},"woke_agent_id":15}"#
            )
        }
        let (store, model) = try connectedStore()
        CompanyFixture.threadsPage(model)
        store.send("Cut it", on: 8, waking: 15)
        await eventually { model.comments[8]?.last?.id == 31 }
        XCTAssertEqual(model.wakes[8]?.last?.agentID, 15, "the thread says whom the message woke")
        XCTAssertNil(model.openQuestion(ThreadKey(agentID: 15, issueID: 8)))
        let request = try XCTUnwrap(FakeServer.requests.first)
        XCTAssertEqual(request.httpMethod, "POST")
        let sent = body(request)
        XCTAssertEqual(sent["body"] as? String, "Cut it")
        XCTAssertNotNil(sent["idempotency_key"] as? String, "a retry must not post twice")
        XCTAssertEqual(sent["wake_agent_id"] as? Int, 15, "API minor 14: the message wakes the thread's agent")

        store.send("   ", on: 8, waking: 15)
        let approval = ApprovalInfo(
            id: 1, kind: "sprint_commit", agentID: nil, issueID: nil, requestedBy: 3, expiresAt: nil, fields: [:])
        store.replyOnly(approval, text: "no issue to reply on")
        try await Task.sleep(for: .milliseconds(100))
        XCTAssertEqual(FakeServer.requests.count, 1, "a blank message and an issue-less reply send nothing")
    }
}
