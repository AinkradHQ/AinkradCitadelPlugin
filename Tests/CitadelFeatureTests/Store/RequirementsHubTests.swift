import AinkradAppKit
import Foundation
import XCTest

@testable import CitadelFeature

/// Screens 12 and 13: the list and its filters, composer targeting and answer routing (decisions #44, #45), the plan
/// tree's numbers and glyphs, artifact grouping, filtering and safe file names.
@MainActor
final class RequirementsHubTests: XCTestCase {
    private func model() -> CompanyModel {
        let model = CompanyFixture.model()
        CompanyFixture.requirementsPage(model)
        return model
    }

    private func question(_ id: Int64, agent: Int64, at: Date, open: Bool = true) -> QuestionInfo {
        QuestionInfo(
            id: id, agentID: agent, issueID: id, issueKey: "CIT-\(id)", requirementID: 12, runID: nil, text: "?",
            options: [], state: open ? "open" : "answered", askedAt: at)
    }

    func testTheListFiltersAndSaysWhatWaits() {
        let model = model()
        XCTAssertEqual(model.requirementList(.open).map(\.key), ["R-12", "R-11", "R-10", "R-9", "R-8"])
        XCTAssertEqual(model.requirementList(.needsYou).map(\.key), ["R-12", "R-11"], "a question, a plan to approve")
        XCTAssertEqual(model.requirementList(.done).map(\.key), ["R-7"])
        let r12 = model.requirements[0]
        XCTAssertEqual(model.waitingCount(r12), 1)
        XCTAssertEqual(model.requirementSubtitle(r12), "CEO · 5 / 31 pts")
        XCTAssertEqual(model.requirementSubtitle(model.requirements[1]), "PO Mira · 13 pts")
        XCTAssertEqual(model.requirementSubtitle(model.requirements[3]), "CEO drafting · no work yet")
        XCTAssertEqual(model.ownerName(1), "Aldric (CEO)")
        XCTAssertEqual(model.ownerName(3), "Mira (PO)", "the PO owns it after hand-off")
        XCTAssertEqual(model.askerName(4), "Kestrel (Dev)")
    }

    func testTheComposerTargetsTheNewestOpenQuestionUntilCleared() throws {
        let base = Date(timeIntervalSince1970: 1_800_000_000)
        let older = question(1, agent: 5, at: base)
        let newer = question(2, agent: 4, at: base.addingTimeInterval(60))
        let answered = question(3, agent: 9, at: base.addingTimeInterval(120), open: false)
        var thread = RequirementThread(
            requirementID: 12, ownerAgentID: 1, toQuestionID: nil,
            items: [.question(older, answer: nil), .question(newer, answer: nil), .question(answered, answer: "ok")])
        XCTAssertEqual(thread.target(cleared: false), .question(newer), "the newest open one")
        XCTAssertEqual(thread.target(cleared: false).post.questionID, 2)
        XCTAssertFalse(thread.target(cleared: false).post.toOwner)
        thread.toQuestionID = 1
        XCTAssertEqual(thread.target(cleared: false), .question(older), "the server's to_question_id wins")
        XCTAssertEqual(thread.target(cleared: true), .owner(agentID: 1), "a cleared chip talks to the owner")
        XCTAssertEqual(thread.target(cleared: true).post.questionID, nil)
        XCTAssertTrue(thread.target(cleared: true).post.toOwner)

        thread.answered(1, with: "yes")
        XCTAssertEqual(thread.target(cleared: false), .question(newer), "the answer moved the target on")
        guard case .question(let receipt, let answer) = thread.items[0] else { return XCTFail("not a question") }
        XCTAssertFalse(receipt.isOpen)
        XCTAssertEqual(answer, "yes")
        thread.answered(2, with: "p8")
        XCTAssertEqual(thread.target(cleared: false), .owner(agentID: 1), "nothing open: the owner")
        XCTAssertNil(thread.toQuestionID)

        let handedOff = RequirementThread(requirementID: 12, ownerAgentID: 3, toQuestionID: nil, items: [])
        XCTAssertEqual(handedOff.target(cleared: false), .owner(agentID: 3), "the PO after hand-off")
    }

    func testThreadLinesGroupArtifacts() {
        let a = CompanyFixture.artifacts
        let lines = HubLine.lines([
            .artifact(a[0]), .artifact(a[1]), .question(question(1, agent: 4, at: .distantPast), answer: nil),
            .artifact(a[2]),
        ])
        XCTAssertEqual(lines.count, 3)
        XCTAssertEqual(lines[0], .artifacts([a[0], a[1]]))
        XCTAssertEqual(lines[2], .artifacts([a[2]]))
    }

    func testThePlanTreeNumbersAndGlyphs() throws {
        let model = model()
        let plan = try XCTUnwrap(model.requirementsPage.plans[12])
        XCTAssertEqual(plan.percent, 16)
        XCTAssertEqual(plan.allTasks.count, 10)
        XCTAssertEqual(plan.inReview, 1)
        let glyphs = plan.epics[0].tasks.map { model.glyph($0) }
        XCTAssertEqual(glyphs, [.done, .review, .waiting, .blocked], "CIT-62 asks you")
        XCTAssertEqual(plan.epics[1].tasks.map { model.glyph($0).glyph }, ["✓", "▶", "○", "○"])
        XCTAssertTrue(plan.epics[0].started)
        XCTAssertFalse(plan.epics[2].started)
        XCTAssertEqual(model.taskMeta(plan.epics[0].tasks[0]), "done · 1h 40m · 96k tok")
        XCTAssertEqual(model.taskMeta(plan.epics[0].tasks[1]), "2 PRs · QA ✓ · merge waits")
        XCTAssertEqual(model.taskMeta(plan.epics[0].tasks[2]), "asks you · 2 repos")
        XCTAssertEqual(plan.diff?.summary, "+1 task since approval (CIT-60, +3 pts)")
        XCTAssertEqual(TaskGlyph(state: "done", asksYou: true), .done, "a done task never waits")

        XCTAssertEqual(Burndown.span(plan), 3 + 26 / 2.5, accuracy: 0.001, "ideal reaches zero at the pace")
    }

    func testDecidedPermissionsFoldAndWorkStartsAfterTheApprovedPlan() {
        func permission(_ id: Int64, _ tool: String, status: String = "approved") -> ThreadItem {
            .approval(
                ApprovalInfo(
                    id: id, kind: "permission_escalation", agentID: 4, issueID: 1, requestedBy: 4, expiresAt: nil,
                    fields: ["tool": tool], status: status), at: .distantPast)
        }
        let plan = ThreadItem.approval(
            ApprovalInfo(
                id: 9, kind: "plan_approval", agentID: nil, issueID: nil, requestedBy: 3, expiresAt: nil, fields: [:],
                status: "approved"), at: .distantPast)
        let lines = HubLine.lines(
            [
                plan, permission(1, "Bash"), permission(2, "Bash"), permission(3, "WebFetch"),
                permission(4, "Bash", status: "pending"),
            ],
            started: "▶ Work started · 4 agents", closed: "✓ Done · 21 pts")
        XCTAssertEqual(lines.count, 5)
        XCTAssertEqual(lines[1], .system("▶ Work started · 4 agents"))
        guard case .permissions(let folded) = lines[2] else { return XCTFail("decided permissions fold") }
        XCTAssertEqual(HubLine.toolCounts(folded), "Bash ×2 · WebFetch ×1")
        if case .item(.approval(let pending, _)) = lines[3] {
            XCTAssertEqual(pending.status, "pending", "a pending permission keeps its own card")
        } else {
            XCTFail("pending permission stays a card")
        }
        XCTAssertEqual(lines[4], .system("✓ Done · 21 pts"))
    }

    func testArtifactsGroupByDayAndFilter() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let now = Date(timeIntervalSince1970: 1_800_000_000)  // a fixed instant, not the clock
        func at(_ ago: TimeInterval, _ id: Int64, kind: String = "report", agent: Int64 = 9) -> ArtifactInfo {
            ArtifactInfo(
                id: id, name: "f\(id).md", kind: kind, mime: "text/markdown", size: 10, preview: "text", sha256: "",
                agentID: agent, issueID: id, requirementID: nil, runID: nil, createdAt: now.addingTimeInterval(-ago),
                redactions: 0)
        }
        let items = [at(60, 1), at(3 * 86_400, 2), at(30 * 86_400, 3), at(120, 4, kind: "screenshot", agent: 4)]
        let groups = ArtifactGroup.groups(items, now: now, calendar: calendar)
        XCTAssertEqual(groups.map(\.title), ["Today", "Earlier this week", "Older"])
        XCTAssertEqual(groups[0].items.map(\.id), [1, 4], "newest first")

        XCTAssertEqual(items.filter { ArtifactFilter(kind: "screenshot").matches($0) }.map(\.id), [4])
        XCTAssertEqual(items.filter { ArtifactFilter(agentID: 9).matches($0) }.map(\.id), [1, 2, 3])
        let byRequirement = ArtifactFilter(requirementID: 12)
        XCTAssertEqual(
            items.filter { byRequirement.matches($0, requirementOf: { $0 == 2 ? 12 : nil }) }.map(\.id), [2],
            "an artifact belongs to its issue's requirement")
    }

    func testArtifactMappingAndSafeNames() {
        let model = model()
        CompanyFixture.artifactsPage(model)
        XCTAssertEqual(model.filteredArtifacts.count, 9)
        let report = CompanyFixture.artifacts[0]
        XCTAssertEqual(report.typeLabel(), "report · md")
        XCTAssertEqual(
            CompanyFixture.artifacts[1].typeLabel(imageSize: CGSize(width: 1440, height: 900)), "png · 1440×900")
        XCTAssertEqual(CompanyFixture.artifacts[5].typeLabel(), "log · 84 KB")
        XCTAssertEqual(model.references(report), ["CIT-61", "R-12"])
        XCTAssertEqual(ArtifactInfo.shortHash(report.sha256), "9f2c…e1")
        XCTAssertTrue(model.artifactsCrumb(company: "Ainkrad", now: CompanyFixture.now).hasSuffix("212 MB of 2 GB"))

        XCTAssertEqual(ArtifactInfo.safeFileName("../../etc/passwd", id: 1), "_.._etc_passwd")
        XCTAssertEqual(ArtifactInfo.safeFileName(".zshrc", id: 2), "zshrc", "never a hidden file")
        XCTAssertEqual(ArtifactInfo.safeFileName("a/b:c\\d\ne.md", id: 3), "a_b_c_d_e.md")
        XCTAssertEqual(ArtifactInfo.safeFileName("///", id: 4), "artifact-4")
        XCTAssertEqual(ArtifactInfo.safeFileName("", id: 5), "artifact-5")
        XCTAssertEqual(ArtifactInfo.safeFileName(String(repeating: "x", count: 400), id: 6).count, 200)
    }

    // MARK: - Routing an answer

    private func sentJSON(_ request: URLRequest) -> [String: Any] {
        guard let stream = request.httpBodyStream else {
            return (request.httpBody.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]) ?? [:]
        }
        stream.open()
        var bytes = Data()
        var buffer = [UInt8](repeating: 0, count: 4096)
        while stream.hasBytesAvailable {
            let n = stream.read(&buffer, maxLength: buffer.count)
            if n <= 0 { break }
            bytes.append(buffer, count: n)
        }
        stream.close()
        return (try? JSONSerialization.jsonObject(with: bytes) as? [String: Any]) ?? [:]
    }

    func testAnAnswerGoesToTheAskerAndAClearedChipToTheOwner() async throws {
        var posts = 0  // the route runs under FakeServer's lock: count here, never read `requests` there
        FakeServer.serve { request in
            guard request.url?.path == "/api/v1/requirements/12/thread" else { return .init(status: 404) }
            posts += 1
            // The first post answers Kestrel; the second is the message to the owner.
            guard posts == 1 else { return .init(json: #"{"comment_id":90,"woke_agent_id":1}"#) }
            return .init(
                json:
                    #"{"answered":{"id":7,"asked_by_agent_id":4,"issue_id":62,"issue_key":"CIT-62","question":"?","options":[],"state":"answered","created_at":"2026-10-23T09:00:00.000Z","answer":".p8"},"woke_agent_id":4,"woke_issue_id":62}"#
            )
        }
        let settings = SettingsStore(documents: MemoryDocs())
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_FAKE_fixture", company: 1,
            session: FakeServer.session())
        let model = model()
        store.model = model
        let thread = try XCTUnwrap(model.requirementsPage.threads[12])
        let target = thread.target(cleared: false)
        guard case .question(let question) = target else { return XCTFail("the open question is the target") }
        XCTAssertEqual(question.agentID, 4, "Kestrel asked it")

        store.send(".p8 — I'll upload it", requirement: 12, to: target)
        await eventually { model.requirementsPage.threads[12]?.openQuestions.isEmpty == true }
        let answer = sentJSON(try XCTUnwrap(FakeServer.requests.first))
        XCTAssertEqual(answer["question_id"] as? Int, 7)
        XCTAssertNil(answer["to_owner"], "an answer is not a message to the CEO")
        XCTAssertEqual(model.questions.first { $0.id == 7 }?.state, "answered", "the agent thread clears too")
        XCTAssertEqual(
            model.requirementsPage.threads[12]?.target(cleared: false), .owner(agentID: 1),
            "nothing left open: the owner")

        store.send("Thanks — ship it", requirement: 12, to: .owner(agentID: 1))
        await eventually { FakeServer.requests.count == 2 }
        let message = sentJSON(FakeServer.requests[1])
        XCTAssertEqual(message["to_owner"] as? Bool, true)
        XCTAssertNil(message["question_id"])
    }
}
