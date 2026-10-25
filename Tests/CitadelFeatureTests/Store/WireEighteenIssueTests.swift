import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 18, tranche B1: the work-item drawer's edits and activity, epics, and the kinds and levels it names.
/// The JSON bodies a route saw, in order (a request's body stream reads once, so the route takes them as they come).
final class SentBodies: @unchecked Sendable {
    private let lock = NSLock()
    private var bodies: [[String: Any]] = []

    func add(_ data: Data?) {
        guard let data, let json = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else { return }
        lock.withLock { bodies.append(json) }
    }

    var all: [[String: Any]] { lock.withLock { bodies } }
}

@MainActor
final class WireEighteenIssueTests: XCTestCase {
    nonisolated static let issue =
        #"{"id":42,"key":"CIT-42","project_id":1,"number":42,"kind":"chore","title":"Replay, renamed","body":"why","state":"in_progress","rank":1.0,"priority":true,"priority_level":"urgent","labels":[],"criteria":[{"text":"Lease survives a restart","done":true}]}"#

    private func make(minor: Int?) throws -> (CitadelStore, CompanyModel) {
        let store = try Wire17.store(minor: minor)
        let model = try XCTUnwrap(store.model)
        CompanyFixture.projectWorkPage(model)
        return (store, model)
    }

    private func item(_ model: CompanyModel) throws -> WorkItem {
        try XCTUnwrap(model.projectsPage.work[1]?.items.first { $0.id == 42 })
    }

    func testEditingTheDrawersFieldsPatchesTheIssueWithOnlyThatField() async throws {
        let (store, model) = try make(minor: 18)
        let sent = SentBodies()
        FakeServer.serve { request in
            if request.httpMethod == "PATCH" { sent.add(request.body17) }
            return .init(json: Self.issue)
        }
        let before = try item(model)
        store.setTitle(before, "  Replay, renamed ", project: 1)
        await eventually { sent.all.count == 1 }
        XCTAssertEqual(sent.all[0] as NSDictionary, ["title": "Replay, renamed"] as NSDictionary)
        await eventually { (try? self.item(model))?.priorityLevel == "urgent" }
        XCTAssertEqual(try item(model).kind, "chore", "the server's answer replaces the optimistic row")

        store.setKind(before, "spike", project: 1)
        await eventually { sent.all.count == 2 }
        store.setPriority(before, level: "low", project: 1)
        await eventually { sent.all.count == 3 }
        store.setBody(before, "new text", project: 1)
        await eventually { sent.all.count == 4 }
        store.setCriteria(before, [CriterionInfo(text: "Lease survives a restart", done: true)], project: 1)
        await eventually { sent.all.count == 5 }
        XCTAssertEqual(sent.all[1]["kind"] as? String, "spike")
        XCTAssertEqual(sent.all[2]["priority_level"] as? String, "low")
        XCTAssertEqual(sent.all[3]["body"] as? String, "new text")
        let criteria = try XCTUnwrap(sent.all[4]["criteria"] as? [[String: Any]])
        XCTAssertEqual(criteria.first?["text"] as? String, "Lease survives a restart")
        XCTAssertEqual(criteria.first?["done"] as? Bool, true)
    }

    func testARefusedEditPutsTheItemBackAndShowsTheServersWords() async throws {
        let (store, model) = try make(minor: 18)
        FakeServer.serve { _ in .init(status: 400, json: Wire.refusal("invalid", "a title is 1 to 200 characters")) }
        let before = try item(model)
        store.setPriority(before, level: "urgent", project: 1)
        _ = try await Wire17.sent("PATCH", "/api/v1/issues/42")
        await eventually { (try? self.item(model)) == before }
        XCTAssertEqual(try item(model).priorityLevel, "high", "the fixture level comes back")
    }

    func testAnOlderServerGetsNoIssueEditAndKeepsItsFlag() async throws {
        let (store, model) = try make(minor: 17)
        FakeServer.serve { _ in .init(status: 404, json: Wire.refusal("not_found", "no route")) }
        let before = try item(model)
        store.setTitle(before, "Other", project: 1)
        store.setKind(before, "chore", project: 1)
        store.setPriority(before, level: "low", project: 1)
        store.setBody(before, "x", project: 1)
        store.setCriteria(before, [CriterionInfo(text: "a")], project: 1)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(FakeServer.requests.filter { $0.httpMethod != "GET" }.isEmpty)
        XCTAssertEqual(try item(model), before)
        XCTAssertFalse(store.hasTrancheB)
        XCTAssertEqual(before.level, "high", "the bool flag still reads as High")
    }

    func testTheDrawersActivityComesFromTheIssuesOwnListOnlyFromMinor18() async throws {
        let page =
            #"{"items":[{"seq":9,"at":"2026-10-24T10:00:00.000Z","actor":{"kind":"user","user_id":1},"action":"issue.edited","details":{}}]}"#
        var (store, model) = try make(minor: 18)
        FakeServer.serve { _ in .init(json: page) }
        store.openItem(42)
        await eventually { model.projectsPage.itemActivity[42]?.first?.action == "issue.edited" }
        XCTAssertTrue(FakeServer.requests.contains { $0.url?.path == "/api/v1/issues/42/activity" })

        (store, model) = try make(minor: 17)
        FakeServer.serve { _ in .init(json: page) }
        store.openItem(42)
        await eventually { model.projectsPage.itemActivity[42] != nil }
        XCTAssertFalse(FakeServer.requests.contains { $0.url?.path == "/api/v1/issues/42/activity" })
    }

    func testAnEpicEditPatchesItsColourDatesAndRequirement() async throws {
        let (store, model) = try make(minor: 18)
        FakeServer.serve { _ in
            .init(
                json:
                    ##"{"id":1,"key":"E-1","number":1,"project_id":1,"title":"Event stream","status":"open","color":"#a78bfa","starts_on":"2026-10-01","ends_on":"2026-11-10","requirement_id":12}"##
            )
        }
        let epic = try XCTUnwrap(model.projectsPage.work[1]?.epics.first)
        store.editEpic(
            epic, project: 1, color: "#a78bfa", startsOn: "2026-10-01", endsOn: "2026-11-10", requirement: 12)
        let body = try await Wire17.sent("PATCH", "/api/v1/epics/1")
        XCTAssertEqual(body["color"] as? String, "#a78bfa")
        XCTAssertEqual(body["starts_on"] as? String, "2026-10-01")
        XCTAssertEqual(body["ends_on"] as? String, "2026-11-10")
        XCTAssertEqual(body["requirement_id"] as? Int, 12)
        await eventually { model.projectsPage.work[1]?.epics.first?.requirementID == 12 }
        XCTAssertNotNil(model.projectsPage.work[1]?.epics.first?.startsOn)

        let (old, _) = try make(minor: 17)
        FakeServer.serve { _ in .init(status: 404) }
        old.editEpic(epic, project: 1, color: "#a78bfa", startsOn: nil, endsOn: nil, requirement: nil)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(Wire17.didSend("PATCH", "/api/v1/epics/1"))
    }

    func testTheIssueAndEpicSchemasReadTheNewFieldsAndSurviveTheirAbsence() throws {
        let decoder = JSONDecoder()
        let full = try decoder.decode(Schemas.Issue.self, from: Data(Self.issue.utf8))
        let item = WorkItem(full)
        XCTAssertEqual(item.priorityLevel, "urgent")
        XCTAssertEqual(item.criteria, [CriterionInfo(text: "Lease survives a restart", done: true)])
        let bare = try decoder.decode(
            Schemas.Issue.self,
            from: Data(
                #"{"id":1,"key":"CIT-1","project_id":1,"number":1,"kind":"task","title":"t","body":"","state":"todo","rank":1,"priority":false,"labels":[]}"#
                    .utf8))
        XCTAssertNil(WorkItem(bare).priorityLevel)
        XCTAssertEqual(WorkItem(bare).criteria, [])
        XCTAssertEqual(WorkItem(bare).level, "low")
        let epic = try decoder.decode(
            Schemas.Epic.self,
            from: Data(#"{"id":1,"key":"E-1","number":1,"project_id":1,"title":"t","status":"open"}"#.utf8))
        XCTAssertNil(EpicInfo(epic).color)
        XCTAssertNil(EpicInfo(epic).startsOn)
    }
}
