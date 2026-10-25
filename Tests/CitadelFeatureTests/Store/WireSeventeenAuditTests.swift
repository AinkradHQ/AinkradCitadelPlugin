import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 17, audit log: the actor chip is asked of the server (`actor=user|agent|system`), not filtered here.
@MainActor
final class WireSeventeenAuditTests: XCTestCase {
    /// Item 3: each chip sends its actor kind; "Everyone" sends none.
    func testTheActorChipsAskTheServerForTheirKind() async throws {
        let store = try Wire17.store()
        let page = try XCTUnwrap(store.model?.limitsPage)
        let expected = [("you", "user"), ("agents", "agent"), ("system", "system"), ("all", nil)]
        for (chip, kind) in expected {
            FakeServer.serve { _ in .init(json: #"{"items":[]}"#) }
            page.auditLog = nil
            page.auditActor = chip
            store.loadAuditLog()
            await eventually { page.auditLog != nil }
            // Other suites' screens may still be loading the same fake server, so match the sent actors, not the order.
            if let kind {
                XCTAssertTrue(FakeServer.requests.contains { $0.query["actor"] == kind }, "chip \(chip)")
            } else {
                XCTAssertFalse(FakeServer.requests.contains { $0.query["actor"] != nil }, "chip \(chip)")
            }
        }
    }

    /// Item 3, gate: an older server gets no `actor` (its chips filter the loaded rows, as before).
    func testAnOlderServerIsNotAskedForAnActor() async throws {
        let store = try Wire17.store(minor: 16)
        let page = try XCTUnwrap(store.model?.limitsPage)
        FakeServer.serve { _ in .init(json: #"{"items":[]}"#) }
        page.auditActor = "you"
        store.loadAuditLog()
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(FakeServer.requests.contains { $0.query["actor"] != nil })
    }
}
