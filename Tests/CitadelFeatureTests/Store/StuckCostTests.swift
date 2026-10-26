import AinkradAppKit
import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// Screens 08 and 09: stuck vs slowing, the lead a fix goes to, the per-day arithmetic, the period starts, the
/// budget words, the CSV — and the transitions a fix sends.
@MainActor
final class StuckCostTests: XCTestCase {
    func testStuckIsSplitFromSlowingAndFilteredByProject() {
        let model = CompanyFixture.model()
        CompanyFixture.stuckPage(model)
        let all = model.stuckList(project: nil)
        XCTAssertEqual(all.stuck.map(\.issueID), [49, 9, 55])
        XCTAssertEqual(all.slowing.map(\.issueID), [58, 60])
        XCTAssertEqual(model.stuckList(project: 2).stuck.map(\.issueID), [9])
        XCTAssertEqual(model.lead(ofProject: 1)?.name, "Toma")
        XCTAssertEqual(model.lead(ofProject: 2)?.name, "Juno")
        XCTAssertNil(model.lead(ofProject: 3), "the Launch team has no lead")
    }

    func testAStuckIssueMapsTheEnginesRecommendation() throws {
        let stuck = StuckInfo(
            try EventFrame.decoder.decode(
                Schemas.StuckIssue.self,
                from: Data(
                    #"{"kind":"agent_paused_by_breaker","issue_id":55,"agent_id":4,"reason":"loop breaker","action":"escalated","repair":"escalate","last_repair":{"action":"escalate","at":"2026-10-23T09:00:00.000Z"}}"#
                        .utf8)))
        XCTAssertEqual(stuck.repair, "escalate")
        XCTAssertEqual(stuck.lastRepair, "escalate")
        XCTAssertNotNil(stuck.lastRepairAt)
        XCTAssertFalse(stuck.isSlowing)
        XCTAssertEqual(stuck.glyph, "↻")
    }

    func testPeriodsStartWhereTheyShould() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 23, hour: 15)))
        let day = { (d: Int) in calendar.date(from: DateComponents(year: 2026, month: 10, day: d)) }
        XCTAssertEqual(CostPeriod.today.start(now: now, sprintStart: nil, calendar: calendar), day(23))
        XCTAssertEqual(CostPeriod.month.start(now: now, sprintStart: nil, calendar: calendar), day(1))
        XCTAssertEqual(CostPeriod.sprint.start(now: now, sprintStart: day(20), calendar: calendar), day(20))
        XCTAssertNil(CostPeriod.sprint.start(now: now, sprintStart: nil, calendar: calendar))
    }

    func testTaskDollarsAreNeverZeroForAnUnpricedRun() {
        let model = CompanyFixture.model()
        CompanyFixture.costPage(model)
        let words = Dictionary(uniqueKeysWithValues: model.costTasks.map { ($0.key, $0.dollarsWord) })
        XCTAssertEqual(words["CIT-42"], "$1.90")
        XCTAssertEqual(words["CIT-62"], "sub")
        XCTAssertEqual(words["AMC-12"], "unpriced")
        let totals = SpendTotals(model.costTasks)
        XCTAssertEqual(totals.unpricedTokens, 2_100_000)
        XCTAssertEqual(totals.subscriptionTokens, 244_000)
        XCTAssertEqual(model.costByProject().map(\.key), ["AMC", "CIT", "MKT"])
    }

    func testBudgetsSayOkWarnOrStoppedAndWhereTheirWarnComesFrom() {
        let model = CompanyFixture.model()
        let quill = model.budgets[0]
        XCTAssertEqual(model.budgetWord(quill).word, "warn")
        var full = quill
        full.spent = full.cap
        XCTAssertEqual(model.budgetWord(full).word, "stopped")
        XCTAssertEqual(model.budgetWord(model.budgets[2]).word, "ok")
        XCTAssertEqual(model.warnScope(quill), .inherited(from: "server"))
        var set = quill
        set.warnPercent = 70
        XCTAssertEqual(model.warnScope(set), .overridden(at: "agent", inheritedValue: "server 80%"))
    }

    func testTheCSVQuotesTitlesAndKeepsDollarsExact() {
        let task = TaskCostInfo(
            issueID: 1, key: "CIT-1", title: "Fix \"a, b\"", tokens: 10, unpricedTokens: 0, subscriptionTokens: 0,
            costMicros: 1_900_000, secs: 60, runs: 1, pricedRuns: 1, unpricedRuns: 0, subscriptionRuns: 0)
        let lines = costCSV([task]).split(separator: "\n")
        XCTAssertEqual(lines.count, 2)
        XCTAssertEqual(lines[1], #"CIT-1,"Fix ""a, b""",10,10,0,0,1.90,60,1"#)
    }

    func testAFixReassignsToTheLead() async throws {
        FakeServer.serve { _ in .init(json: #"{"id":49}"#) }
        let settings = SettingsStore(documents: MemoryDocs())
        settings.update { $0.server = "https://citadel.example.com" }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_FAKE_fixture", company: 1,
            session: FakeServer.session())
        let model = CompanyFixture.model()
        CompanyFixture.stuckPage(model)
        store.model = model
        store.reassign(model.stuck[0], to: 7)
        await eventually { FakeServer.requests.contains { $0.url?.path == "/api/v1/issues/49/reassign" } }
        let request = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == "/api/v1/issues/49/reassign" })
        let body = try XCTUnwrap(
            request.httpBodyStream.flatMap { stream -> Data? in
                stream.open()
                defer { stream.close() }
                var data = Data()
                var buffer = [UInt8](repeating: 0, count: 1024)
                while stream.hasBytesAvailable {
                    let n = stream.read(&buffer, maxLength: buffer.count)
                    if n <= 0 { break }
                    data.append(buffer, count: n)
                }
                return data
            } ?? request.httpBody)
        let json = try XCTUnwrap(JSONSerialization.jsonObject(with: body) as? [String: Any])
        XCTAssertEqual(json["agent_id"] as? Int, 7)
    }
}
