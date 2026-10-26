import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 20 (P3): "Waiting on you" shows its age; an issue with no explicit repo carries a warning.
@MainActor
final class WireTwentyWaitingAndRepoTests: XCTestCase {
    private let now = Date(timeIntervalSince1970: 1_800_000_000)

    func testOldestWaitIsTheEarliestOfApprovalsQuestionsAndStuck() {
        let model = CompanyModel(companyID: 1)
        XCTAssertNil(model.oldestWaitLine(now: now), "nothing waits")
        model.approvals = [
            ApprovalInfo(
                id: 1, kind: "pr_merge", requestedBy: 1, createdAt: now.addingTimeInterval(-600), fields: [:]),
            ApprovalInfo(id: 2, kind: "pr_merge", requestedBy: 1, createdAt: nil, fields: [:]),
        ]
        XCTAssertEqual(model.oldestWaitLine(now: now), "oldest 10m")
        model.questions = [
            QuestionInfo(
                id: 1, agentID: 1, issueID: 1, issueKey: "A-1", text: "?", options: [], state: "open",
                askedAt: now.addingTimeInterval(-3 * 3600)),
            QuestionInfo(
                id: 2, agentID: 1, issueID: 1, issueKey: "A-1", text: "?", options: [], state: "answered",
                askedAt: now.addingTimeInterval(-9 * 3600)),
        ]
        XCTAssertEqual(model.oldestWaitLine(now: now), "oldest 3h", "an answered question does not wait")
    }

    func testNoTimestampsMeansNoAge() {
        let model = CompanyModel(companyID: 1)
        model.approvals = [ApprovalInfo(id: 1, kind: "pr_merge", requestedBy: 1, fields: [:])]
        XCTAssertNil(model.oldestWaitLine(now: now))
    }

    func testRepoWarningIsGatedOnMinor20() throws {
        var issue = IssueInfo(id: 1, key: "A-1", title: "t", projectID: 1)
        issue.repoImplicit = true
        XCTAssertEqual(CitadelStore.repoImplicitMinor, 20)
        XCTAssertNil(try Wire17.store(minor: 19).repoWarning(issue, primary: "core"))
        XCTAssertEqual(
            try Wire17.store(minor: 20).repoWarning(issue, primary: "core"), "No explicit repo — uses core")
        issue.repoImplicit = false
        XCTAssertNil(try Wire17.store(minor: 20).repoWarning(issue, primary: "core"))
        XCTAssertNil(try Wire17.store(minor: 20).repoWarning(nil, primary: "core"))
    }
}
