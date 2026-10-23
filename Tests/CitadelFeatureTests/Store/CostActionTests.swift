import Foundation
import XCTest

@testable import CitadelFeature

/// 08 and 09 wired to the server: what each fix, price and budget edit sends, the spend series and breakdown, the
/// forms' validation, and a refusal shown as the 11 G banner.
@MainActor
final class CostActionTests: XCTestCase {
    private func store() throws -> CitadelStore {
        let settings = SettingsStore(documents: MemoryDocs())
        settings.update { $0.server = "https://citadel.example.com" }
        let store = CitadelStore(
            settings: settings, secrets: MemorySecrets(), session: FakeServer.session(),
            connector: FakeSockets().connector)
        store.server = CitadelServer(
            address: try ServerAddress("https://citadel.example.com"), deviceKey: "ck_dev_k", company: 1,
            session: FakeServer.session())
        let model = CompanyFixture.model()
        CompanyFixture.stuckPage(model)
        store.model = model
        return store
    }

    private func sent(_ path: String) async throws -> [String: Any] {
        await eventually { FakeServer.requests.contains { $0.url?.path == path } }
        let request = try XCTUnwrap(FakeServer.requests.first { $0.url?.path == path })
        XCTAssertEqual(request.httpMethod, path.hasSuffix("/budgets") ? "PUT" : "POST")
        guard let data = request.sentBody, !data.isEmpty else { return [:] }
        return try XCTUnwrap(JSONSerialization.jsonObject(with: data) as? [String: Any])
    }

    func testStuckFixesHitTheirEndpoints() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { _ in .init(json: #"{"agent_id":5,"wake_id":1,"wake_status":"pending"}"#) }
        store.nudge(model.stuck[4])
        _ = try await sent("/api/v1/issues/60/nudge")
        FakeServer.serve { _ in .init(json: "{}") }
        store.moveToBacklog(model.stuck[2])
        _ = try await sent("/api/v1/issues/55/backlog")
    }

    func testWakeFindsTheSleepingRunnerWithTheAgentsTags() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { request in
            if request.url?.path == "/api/v1/runners" {
                return .init(
                    json: #"""
                        [{"id":1,"name":"hetzner-1","asleep":false,"harnesses":{},"logins":[],"tags":["linux"],"status":"online"},
                         {"id":3,"name":"ahmed-mbp","asleep":false,"harnesses":{},"logins":[],"tags":["macos","xcode-27"],"status":"offline"}]
                        """#)
            }
            return .init(
                json:
                    #"{"id":3,"name":"ahmed-mbp","asleep":false,"harnesses":{},"logins":[],"tags":["macos"],"status":"offline"}"#
            )
        }
        store.wakeRunner(for: model.stuck[1], when: "when_back")
        let body = try await sent("/api/v1/runners/3/wake")
        XCTAssertEqual(body["when"] as? String, "when_back")
        XCTAssertTrue(model.stuck[1].waitsOnASleepingRunner)
        XCTAssertFalse(model.stuck[0].waitsOnASleepingRunner, "a queued run with no lease is not a sleeping Mac")
    }

    func testSleepingRunnerNeedsEveryTag() {
        let runners = [
            RunnerInfo(id: 1, name: "a", status: "online", healthReason: nil, lastSeenAt: nil, tags: ["macos"]),
            RunnerInfo(id: 2, name: "b", status: "offline", healthReason: nil, lastSeenAt: nil, tags: ["linux"]),
            RunnerInfo(id: 3, name: "c", status: "offline", healthReason: nil, lastSeenAt: nil, tags: ["macos", "x"]),
        ]
        XCTAssertEqual(sleepingRunner(for: ["macos"], in: runners)?.id, 3)
        XCTAssertNil(sleepingRunner(for: ["gpu"], in: runners))
    }

    func testAPriceIsCheckedThenSent() async throws {
        XCTAssertEqual(
            PriceDraft.parse(harness: "opencode", model: " ", input: "1", output: "1", cache: ""), .failure(.noModel))
        XCTAssertEqual(
            PriceDraft.parse(harness: "opencode", model: "qwen3", input: "-1", output: "1", cache: ""),
            .failure(.notAPrice))
        let draft = try PriceDraft.parse(
            harness: "opencode", model: "qwen3-coder", input: "$0.30", output: "1.2", cache: ""
        ).get()
        XCTAssertEqual(draft.cache, 0)
        let store = try store()
        FakeServer.serve { _ in .init(json: "{}") }
        store.setPrice(draft)
        let body = try await sent("/api/v1/prices")
        XCTAssertEqual(body["model"] as? String, "qwen3-coder")
        XCTAssertEqual(body["harness"] as? String, "opencode")
        XCTAssertEqual(body["input_usd_per_mtok"] as? Double, 0.3)
        XCTAssertEqual(body["output_usd_per_mtok"] as? Double, 1.2)
    }

    func testABudgetCapIsSentWithoutItsRaisesAndItsWarnInherits() async throws {
        XCTAssertEqual(BudgetEdit.parse(cap: "2M", warn: ""), .success(BudgetEdit(cap: 2_000_000, warnPercent: nil)))
        XCTAssertEqual(BudgetEdit.parse(cap: "900k", warn: "70"), .success(BudgetEdit(cap: 900_000, warnPercent: 70)))
        XCTAssertEqual(BudgetEdit.parse(cap: "lots", warn: ""), .failure(.cap))
        XCTAssertEqual(BudgetEdit.parse(cap: "1M", warn: "100"), .failure(.warn), "refused, never clamped")
        let store = try store()
        var budget = try XCTUnwrap(store.model?.budgets.first { $0.scope == "department:2" })
        budget.raised = 100_000
        budget.hardStop = false
        FakeServer.serve { _ in .init(json: "{}") }
        store.setBudget(budget, cap: 1_200_000, warnPercent: nil)
        let body = try await sent("/api/v1/companies/1/budgets")
        XCTAssertEqual(body["token_cap"] as? Int, 1_100_000)
        XCTAssertEqual(body["period"] as? String, "month")
        XCTAssertEqual(body["hard_stop"] as? Bool, false)
        XCTAssertNil(body["warn_at_percent"] as? Int)
        let scope = try XCTUnwrap(body["scope"] as? [String: Any])
        XCTAssertEqual(scope["kind"] as? String, "department")
        XCTAssertEqual(scope["department_id"] as? Int, 2)
    }

    func testARefusalBecomesTheBanner() async throws {
        let store = try store()
        let model = try XCTUnwrap(store.model)
        FakeServer.serve { _ in
            .init(status: 400, json: Wire.refusal("invalid_argument", "the issue waits on no agent"))
        }
        store.nudge(model.stuck[4])
        await eventually { store.actionFailure != nil }
        XCTAssertEqual(
            store.actionFailure?.answer,
            ServerAnswer(
                status: 400, code: "invalid_argument", message: "the issue waits on no agent",
                errorID: "err_01JTEST"))
        XCTAssertEqual(store.actionFailure?.title, "Couldn't wake CIT-60's agent")
        XCTAssertEqual(store.actionFailure?.outcome, "Nobody was woken.")
    }

    func testTheSpendSeriesAndBreakdownMap() async throws {
        let spend =
            #"{"cost_usd_micros":1900000,"priced_tokens":95000,"unpriced_tokens":20,"unpriced_runs":1,"subscription_tokens":300,"subscription_runs":2}"#
        FakeServer.serve { request in
            switch request.url?.path {
            case "/api/v1/companies/1/spend":
                XCTAssertEqual(request.query["bucket"], "day")
                return .init(
                    json:
                        #"[{"start":"2026-10-21T00:00:00.000Z","spend":\#(spend)},{"start":"2026-10-22T00:00:00.000Z","spend":\#(spend)}]"#
                )
            case "/api/v1/companies/1/costs/breakdown":
                return .init(
                    json:
                        #"{"since":"2026-10-01T00:00:00.000Z","until":"2026-10-23T00:00:00.000Z","agents":[{"agent_id":4,"spend":\#(spend)}],"departments":[{"department_id":null,"spend":\#(spend)}]}"#
                )
            default: return .init(json: "{}")
            }
        }
        let store = try store()
        let server = try XCTUnwrap(store.server)
        let series = await server.spendSeries(company: 1, bucket: "day", since: Date(timeIntervalSince1970: 0))
        let days = try XCTUnwrap(series)
        XCTAssertEqual(days.count, 2)
        XCTAssertEqual(days[0].totals.costMicros, 1_900_000)
        XCTAssertEqual(days[0].totals.tokens, 95_320)
        XCTAssertEqual(days[1].day, Date(timeIntervalSince1970: 1_792_627_200))
        let read = await server.spendBreakdown(company: 1, since: nil)
        let breakdown = try XCTUnwrap(read)
        XCTAssertEqual(breakdown.agents.first?.id, 4)
        XCTAssertNil(breakdown.departments.first?.id)
        XCTAssertEqual(breakdown.agents.first?.totals.amount, "$1.90")
        XCTAssertEqual(SpendTotals(unpricedTokens: 640_000).amount, "unpriced")
        XCTAssertEqual(SpendTotals(subscriptionTokens: 2_000).amount, "2k tok")
    }

    func testAStuckCardsAgeReads() {
        XCTAssertEqual(stuckAge(2_880), "48m")
        XCTAssertEqual(stuckAge(7_440), "2h 04m")
        XCTAssertEqual(stuckAge(90_000), "1d")
    }

    func testTheChartStartsAWeekBackAtLeast() throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = try XCTUnwrap(TimeZone(identifier: "UTC"))
        let now = try XCTUnwrap(calendar.date(from: DateComponents(year: 2026, month: 10, day: 3, hour: 15)))
        let day = { (d: Int) in calendar.date(from: DateComponents(year: 2026, month: 10, day: d)) }
        let monthStart = CostPeriod.month.start(now: now, sprintStart: nil, calendar: calendar)
        XCTAssertEqual(
            CostPeriod.month.chartStart(now: now, start: monthStart, calendar: calendar),
            calendar.date(from: DateComponents(year: 2026, month: 9, day: 27)))
        XCTAssertEqual(CostPeriod.today.chartStart(now: now, start: day(3), calendar: calendar), day(3))
    }
}

extension URLRequest {
    /// The body, whether set directly or streamed.
    fileprivate var sentBody: Data? {
        if let httpBody { return httpBody }
        guard let stream = httpBodyStream else { return nil }
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
    }
}
