import Foundation
import XCTest

@testable import CitadelFeature

/// The org peek's week for Kestrel: the fixture stages the prototype's 15 runs, 60% succeeded, $1.28 average.
@MainActor
final class OrgPeekFixtureTests: XCTestCase {
    func testKestrelsWeekMatchesThePrototypePeek() {
        let model = CompanyFixture.model()
        CompanyFixture.orgPeekRuns(model)
        let stats = AgentStats(runs: model.agentRuns[4] ?? [])
        XCTAssertEqual(stats.weekTotal, 15)
        XCTAssertEqual(stats.successPercent, 60)
        XCTAssertEqual(stats.averageMicros, 1_280_000)
    }
}
