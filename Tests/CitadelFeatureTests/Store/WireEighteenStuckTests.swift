import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 18, tranche B1: a stuck issue's run, how long it usually takes and the server's own trail.
@MainActor
final class WireEighteenStuckTests: XCTestCase {
    nonisolated static let list =
        #"[{"kind":"in_progress_idle","reason":"Silent for 14 minutes","action":"Nudge it.","repair":"rewake","issue_id":42,"agent_id":4,"run_id":418,"usual_secs":720,"stuck_since":"2026-10-25T09:00:00.000Z","trail":[{"at":"2026-10-25T09:05:00.000Z","what":"run 418 went quiet"},{"at":"2026-10-25T09:00:00.000Z","what":"run 418 started on hetzner-1"}]},{"kind":"todo_idle","reason":"Nothing moved","action":"Wake it.","repair":"rewake","issue_id":43}]"#

    func testTheStuckListReadsTheRunTheUsualTimeAndTheTrail() async throws {
        let store = try Wire17.store(minor: 18)
        FakeServer.serve { _ in .init(json: Self.list) }
        let loaded = await store.server?.stuck()
        let all = try XCTUnwrap(loaded)
        let first = try XCTUnwrap(all.first)
        XCTAssertEqual(first.runID, 418)
        XCTAssertEqual(first.usualSecs, 720)
        XCTAssertEqual(first.trail.map(\.what), ["run 418 went quiet", "run 418 started on hetzner-1"])
        let bare = try XCTUnwrap(all.last)
        XCTAssertNil(bare.runID)
        XCTAssertNil(bare.usualSecs)
        XCTAssertEqual(bare.trail, [], "a server without trail leaves the derived one")
    }

    func testTheServersTrailReadsOldestFirstAndTheLastStepIsWhereItStopped() throws {
        let day = try XCTUnwrap(ProjectLogic.day("2026-10-25"))
        let trail = [
            TrailInfo(at: day.addingTimeInterval(300), what: "went quiet"),
            TrailInfo(at: day, what: "started"),
        ]
        let steps = StuckTrail.serverSteps(trail, isWarn: false)
        XCTAssertEqual(steps.map(\.label), ["started", "went quiet"])
        XCTAssertEqual(steps.map(\.state), [.ok, .bad])
        XCTAssertEqual(StuckTrail.serverSteps(trail, isWarn: true).last?.state, .warn)
        XCTAssertEqual(StuckTrail.serverSteps([], isWarn: true), [])
    }

    func testTheCardUsesTheServersTrailOnlyFromMinor18() throws {
        XCTAssertTrue(try Wire17.store(minor: 18).hasTrancheB)
        XCTAssertFalse(try Wire17.store(minor: 17).hasTrancheB)
        XCTAssertFalse(try Wire17.store(minor: nil).hasTrancheB)
    }
}
