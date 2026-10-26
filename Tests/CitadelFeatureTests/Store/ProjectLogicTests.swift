import XCTest

@testable import CitadelFeature

/// The ported Quest rules (`BoardLogic`, `BacklogLogic`, `SprintLogic`, `ServerInsights`) on `WorkItem`.
final class ProjectLogicTests: XCTestCase {
    private func item(_ id: Int64, _ state: String, rank: Double = 0, owner: Int64? = 7) -> WorkItem {
        WorkItem(id: id, key: "CIT-\(id)", title: "t", projectID: 1, state: state, ownerAgentID: owner, rank: rank)
    }

    func testDropsMapToTheStateMachine() {
        XCTAssertEqual(try? ProjectLogic.step(for: item(1, "backlog"), to: "todo", reviewer: 9).get(), .ready)
        XCTAssertEqual(try? ProjectLogic.step(for: item(1, "todo"), to: "in_progress", reviewer: 9).get(), .start)
        XCTAssertEqual(
            try? ProjectLogic.step(for: item(1, "in_progress"), to: "in_review", reviewer: 9).get(),
            .submitForReview(reviewer: 9))
        XCTAssertEqual(try? ProjectLogic.step(for: item(1, "in_review"), to: "done", reviewer: 9).get(), .approve)
        XCTAssertEqual(
            try? ProjectLogic.step(for: item(1, "in_review"), to: "in_progress", reviewer: 9).get(),
            .requestChanges(assignee: 7))
        XCTAssertEqual(try? ProjectLogic.step(for: item(1, "done"), to: "todo", reviewer: 9).get(), .reopen(next: 7))
    }

    func testActivityWords() {
        XCTAssertEqual(
            ProjectLogic.activityWords(action: "issue.transitioned", details: ["to": "in_review"]),
            "moved it to In review")
        XCTAssertEqual(ProjectLogic.activityWords(action: "issue.transitioned", details: [:]), "moved it")
        XCTAssertEqual(ProjectLogic.activityWords(action: "issue.idle_escalated", details: [:]), "idle escalated")
    }

    func testCIAtAGlance() {
        XCTAssertEqual(ProjectLogic.ci(["success", "failure", "pending"]), "CI failing")
        XCTAssertEqual(ProjectLogic.ci(["success", "pending"]), "CI running")
        XCTAssertEqual(ProjectLogic.ci(["none", "success"]), "CI passing")
        XCTAssertNil(ProjectLogic.ci(["none"]))
    }

    func testRefusals() {
        XCTAssertNil(try? ProjectLogic.step(for: item(1, "in_progress"), to: "in_review", reviewer: nil).get())
        XCTAssertNil(try? ProjectLogic.step(for: item(1, "blocked"), to: "done", reviewer: 9).get())
        XCTAssertNil(try? ProjectLogic.step(for: item(1, "todo"), to: "done", reviewer: 9).get())
    }

    func testWIPRefusesAFullColumnOnly() {
        let items = [item(1, "in_progress"), item(2, "in_progress"), item(3, "todo")]
        XCTAssertNotNil(
            ProjectLogic.wipRefusal(moving: items[2], into: "in_progress", items: items, limits: ["in_progress": 2]))
        XCTAssertNil(
            ProjectLogic.wipRefusal(moving: items[2], into: "in_progress", items: items, limits: ["in_progress": 3]))
        XCTAssertNil(
            ProjectLogic.wipRefusal(moving: items[0], into: "in_progress", items: items, limits: ["in_progress": 1]))
    }

    func testRankOrderAndPlacement() {
        let order = ProjectLogic.ranked([
            item(3, "backlog", rank: 2), item(1, "backlog", rank: 1), item(2, "backlog", rank: 1),
        ])
        XCTAssertEqual(order.map(\.id), [1, 2, 3])
        XCTAssertNil(ProjectLogic.place(1, at: 0, in: order))
        XCTAssertEqual(ProjectLogic.place(3, at: 0, in: order), .before(1))
        XCTAssertEqual(ProjectLogic.place(1, at: 3, in: order), .after(3))
    }

    func testIdealBurndownAndPercentile() {
        XCTAssertEqual(ProjectLogic.ideal(points: 10, days: 3), [10, 5, 0])
        XCTAssertEqual(ProjectLogic.percentile([1, 2, 3, 4, 10], 0.85), 10)
        XCTAssertEqual(ProjectLogic.percentile([1, 2, 3, 4], 0.5), 2)
        XCTAssertNil(ProjectLogic.percentile([], 0.5))
    }

    @MainActor func testBlockedWorkStaysInProgressAndSprintNamesCount() {
        XCTAssertEqual(item(1, "blocked").column, "in_progress")
        XCTAssertEqual(CitadelStore.nextSprintName(after: "S4"), "S5")
        XCTAssertEqual(CitadelStore.nextSprintName(after: nil), "S1")
    }
}
