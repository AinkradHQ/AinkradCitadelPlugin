import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 18, tranche B2: an agent's stats from the server.
@MainActor
final class WireEighteenAgentStatsTests: XCTestCase {
    private let statsJSON = """
        {"avg_cost_micros":1500000,
         "runs_by_day":[{"day":"2026-10-17","runs":1},{"day":"2026-10-18","runs":2},{"day":"2026-10-19","runs":3},
           {"day":"2026-10-20","runs":4},{"day":"2026-10-21","runs":5},{"day":"2026-10-22","runs":6},
           {"day":"2026-10-23","runs":7}],
         "success_by_week":[{"week":"2026-10-12","runs":10,"succeeded":9},{"week":"2026-10-19","runs":0,"succeeded":0}],
         "heatmap":[[1,0,0,0,0,0],[0,2,0,0,0,0],[0,0,0,0,0,0],[0,0,0,0,0,0],[0,0,0,0,0,0],[0,0,0,0,0,0],[0,0,0,0,0,3]],
         "daily_spend":[{"day":"2026-10-22","cost_usd_micros":2000000,"tokens":1000},
           {"day":"2026-10-23","cost_usd_micros":3000000,"tokens":500}]}
        """

    func testTheServersFiguresReplaceTheOnesDerivedFromLoadedRuns() throws {
        let stats = try EventFrame.decoder.decode(Schemas.AgentStats.self, from: Data(statsJSON.utf8))
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        let friday = try XCTUnwrap(utc.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 12)))
        let shown = AgentStats(runs: [], server: stats, now: friday, calendar: utc)
        XCTAssertEqual(shown.week, [3, 4, 5, 6, 7, 0, 0], "only the days of this week, Monday first")
        XCTAssertEqual(shown.weekly, [90, nil])
        XCTAssertEqual(shown.successPercent, 90)
        XCTAssertEqual(shown.averageMicros, 1_500_000)
        XCTAssertEqual(shown.heat[6][5], 3)
        XCTAssertEqual(shown.heatSpan, "last 4 weeks")
        XCTAssertEqual(shown.todayRuns, 7)
        XCTAssertEqual(shown.todayMicros, 3_000_000)
        XCTAssertEqual(AgentStats.burn(server: stats, dollars: true), [2_000_000, 5_000_000])
        XCTAssertEqual(AgentStats.burn(server: stats, dollars: false), [1000, 1500])
        XCTAssertEqual(AgentStats(runs: [], server: nil).heatSpan, "this week", "no server: derived as before")
    }

    func testStatsAreReadFromMinor18AndNotBefore() async throws {
        let store = try Wire17.store(minor: 18)
        FakeServer.serve { _ in .init(json: self.statsJSON) }
        store.loadAgentStats(4)
        await eventually { store.model?.agentStats[4] != nil }
        XCTAssertEqual(store.model?.agentStats[4]?.avgCostMicros, 1_500_000)
        XCTAssertTrue(Wire17.didSend("GET", "/api/v1/agents/4/stats"))

        let older = try Wire17.store(minor: 17)
        FakeServer.serve { _ in .init(json: self.statsJSON) }
        older.loadAgentStats(4)
        try await Task.sleep(for: .milliseconds(300))
        XCTAssertTrue(FakeServer.requests.isEmpty)
        XCTAssertNil(older.model?.agentStats[4])
    }
}
