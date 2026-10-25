import CitadelClient
import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 18, tranche B2: dollar budgets, the issue scope and the unpriced price's apply-from.
@MainActor
final class WireEighteenBudgetsTests: XCTestCase {
    private func standing(_ json: String) throws -> BudgetInfo {
        let decoded = try EventFrame.decoder.decode(Schemas.BudgetStanding.self, from: Data(json.utf8))
        return BudgetInfo(decoded) { _ in "Company" }
    }

    func testADollarBudgetReadsInDollarsAndAnOldOneInTokens() throws {
        let dollars = try standing(
            #"{"budget_id":3,"scope":{"kind":"company","company_id":1},"period":"month","token_cap":0,"usd_cap_micros":900000000,"usd_spent_micros":412000000,"raised_usd_micros":100000000,"warn_at_percent":80,"hard_stop":true,"period_key":"2026-10","spent":5000,"raised":0}"#
        )
        XCTAssertTrue(dollars.isDollars)
        XCTAssertEqual(dollars.pairWord, "$412 / $1,000", "the raise counts in the cap")
        XCTAssertEqual(dollars.fraction, 0.412, accuracy: 0.001)
        let old = try standing(
            #"{"budget_id":4,"scope":{"kind":"issue","issue_id":9},"period":"day","token_cap":2000000,"warn_at_percent":80,"hard_stop":true,"period_key":"2026-10-22","spent":500000,"raised":0}"#
        )
        XCTAssertFalse(old.isDollars)
        XCTAssertEqual(old.pairWord, "500k / 2M tok")
        XCTAssertEqual(old.scope, "issue:9")
    }

    func testDollarsAreParsedAsMillionthsAndNeverNegative() throws {
        XCTAssertEqual(BudgetUnit.parseDollars("$1,250.50"), 1_250_500_000)
        XCTAssertEqual(BudgetUnit.parseDollars("1.5k"), 1_500_000_000)
        XCTAssertNil(BudgetUnit.parseDollars("-3"))
        XCTAssertNil(BudgetUnit.parseDollars("lots"))
        XCTAssertEqual(
            BudgetEdit.parse(cap: "$900", warn: "", unit: .dollars),
            .success(BudgetEdit(cap: 0, usdCap: 900_000_000, warnPercent: nil)))
        XCTAssertEqual(BudgetEdit.parse(cap: "lots", warn: "", unit: .dollars), .failure(.dollars))
    }

    func testANewDollarBudgetSendsItsDollarCapOnlyFromMinor18() async throws {
        let store = try Wire17.store(minor: 18)
        FakeServer.serve { _ in .init(json: "{}") }
        store.addBudget(scope: "issue:7", label: "CIT-7", period: "total", cap: 0, usdCap: 120_000_000)
        let body = try await Wire17.sent("POST", "/api/v1/companies/1/budgets")
        XCTAssertEqual(body["usd_cap_micros"] as? Int, 120_000_000)
        XCTAssertEqual(body["token_cap"] as? Int, 0)
        XCTAssertEqual((body["scope"] as? [String: Any])?["kind"] as? String, "issue")

        let older = try Wire17.store(minor: 17)
        FakeServer.serve { _ in .init(json: "{}") }
        older.addBudget(scope: "company:1", label: "Company", period: "month", cap: 2_000_000, usdCap: 120_000_000)
        let sent = try await Wire17.sent("POST", "/api/v1/companies/1/budgets")
        XCTAssertNil(sent["usd_cap_micros"], "an older server is never sent the dollar cap")
    }

    func testEditingADollarCapKeepsTheTokenCapAndRemovesTheRaise() async throws {
        let store = try Wire17.store(minor: 18)
        var budget = try XCTUnwrap(store.model?.budgets.first { $0.scope == "department:2" })
        budget.usdCap = 500_000_000
        budget.raisedUsd = 100_000_000
        FakeServer.serve { _ in .init(json: "{}") }
        store.editBudgetCap(budget, text: "$600", inheritsWarn: true)
        let body = try await Wire17.sent("PUT", "/api/v1/companies/1/budgets")
        XCTAssertEqual(body["usd_cap_micros"] as? Int, 500_000_000)
    }

    func testPricingPastRunsSendsApplyFromPast() async throws {
        let store = try Wire17.store(minor: 18)
        let draft = PriceDraft(harness: "opencode", model: "qwen3-coder", input: 0.4, output: 1.2, cache: 0)
        FakeServer.serve { _ in .init(json: "{}") }
        store.savePrice(draft, pastToo: true)
        let past = try await Wire17.sent("POST", "/api/v1/prices")
        XCTAssertEqual(past["apply_from"] as? String, "past")
        let older = try Wire17.store(minor: 17)
        FakeServer.serve { _ in .init(json: "{}") }
        older.savePrice(draft, pastToo: true)
        let now = try await Wire17.sent("POST", "/api/v1/prices")
        XCTAssertNil(now["apply_from"])
    }
}
