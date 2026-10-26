import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 19 (R17): the burndown's scope line and the "n/a" ETA only appear on a server that sends them.
@MainActor
final class WireNineteenHonestAggregatesTests: XCTestCase {
    private func plan(scope: [Int]?) throws -> PlanTree {
        let model = try XCTUnwrap(Wire17.store(minor: 19).model)
        CompanyFixture.requirementsPage(model)
        var plan = try XCTUnwrap(model.requirementsPage.plans[12])
        plan.scope = scope
        return plan
    }

    func testTheGateIsMinor19() throws {
        XCTAssertFalse(try Wire17.store(minor: 18).serverSupports(minor: CitadelStore.honestAggregatesMinor))
        XCTAssertTrue(try Wire17.store(minor: 19).serverSupports(minor: CitadelStore.honestAggregatesMinor))
    }

    func testScopeNeedsEveryDay() {
        XCTAssertEqual(HonestAggregates.scope([31, 31, 34]), [31, 31, 34])
        XCTAssertNil(HonestAggregates.scope([31, nil, 34]))
        XCTAssertNil(HonestAggregates.scope([]))
    }

    func testScopeLineOnlyOnASupportingServer() throws {
        let days = try plan(scope: nil).burndown.count
        let withScope = try plan(scope: Array(repeating: 31, count: days))
        XCTAssertEqual(HonestAggregates.scopeLine(withScope, supported: true)?.count, days)
        XCTAssertNil(HonestAggregates.scopeLine(withScope, supported: false))
        XCTAssertNil(HonestAggregates.scopeLine(try plan(scope: nil), supported: true))
        XCTAssertNil(HonestAggregates.scopeLine(try plan(scope: [31]), supported: true))
    }

    func testMissingEtaIsNAOnlyOnASupportingServer() {
        XCTAssertEqual(HonestAggregates.eta(nil, supported: true), "n/a")
        XCTAssertNil(HonestAggregates.eta(nil, supported: false))
        XCTAssertNil(HonestAggregates.eta(nil, supported: true, showsMissing: false))
        XCTAssertNotEqual(HonestAggregates.eta("2026-10-27", supported: true), "n/a")
    }
}
