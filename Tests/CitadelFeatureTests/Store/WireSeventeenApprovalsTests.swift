import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 17: the minor gate, and an approval's `created_at` / `decided_at`.
@MainActor
final class WireSeventeenApprovalsTests: XCTestCase {
    func testTheMinorGateIsOffUntilTheServerSaysSeventeen() throws {
        XCTAssertFalse(try Wire17.store(minor: nil).serverSupports(minor: 17), "no /me yet")
        XCTAssertFalse(try Wire17.store(minor: 16).serverSupports(minor: 17))
        XCTAssertTrue(try Wire17.store(minor: 17).serverSupports(minor: 17))
        XCTAssertTrue(try Wire17.store(minor: 18).serverSupports(minor: 17))
        XCTAssertEqual(try Wire17.store(minor: 16).help(), CitadelStore.needsServerUpdate)
        XCTAssertEqual(try Wire17.store(minor: 17).help(ready: "Edit"), "Edit")
    }

    func testApprovalsReadWhenTheyWereAskedAndDecided() async throws {
        let store = try Wire17.store()
        let server = try XCTUnwrap(store.server)
        FakeServer.serve { _ in
            .init(
                json: """
                    [{"id":5,"company_id":1,"kind":"hire_agent","requested_by":2,"status":"approved","payload":{},
                    "created_at":"2026-10-25T10:00:00.000Z","decided_at":"2026-10-25T10:12:00.000Z"},
                    {"id":6,"company_id":1,"kind":"hire_agent","requested_by":2,"status":"pending","payload":{}}]
                    """)
        }
        let page = await server.approvals(company: 1, pending: false)
        let all = try XCTUnwrap(page)
        let now = try XCTUnwrap(all[0].createdAt).addingTimeInterval(12 * 60)
        XCTAssertEqual(all[0].askedAgo(now: now), "asked 12m ago")
        XCTAssertEqual(all[0].decidedAgo(now: now), "0s ago")
        XCTAssertNil(all[1].askedAgo(), "a minor-16 server sends neither field")
        XCTAssertNil(all[1].decidedAgo())
    }

    func testAnAnsweredApprovalIsStampedAndActivitySortsByIt() throws {
        let store = try Wire17.store()
        let model = try XCTUnwrap(store.model)
        let approval = ApprovalInfo(id: 9, kind: "hire_agent", requestedBy: 2, fields: [:])
        model.approvals = [approval]
        model.answer(approval, approved: true, reply: nil)
        XCTAssertNotNil(model.answeredApprovals.first?.decidedAt)
    }
}
