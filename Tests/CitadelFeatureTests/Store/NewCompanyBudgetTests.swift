import XCTest

@testable import CitadelFeature

/// The New company wizard's `$ / tokens` toggle: the dollar cap is sent only while it is on, and the CEO's share
/// of the company budget.
final class NewCompanyBudgetTests: XCTestCase {
    func testUsdCapOnlyWhileToggleIsOnDollars() {
        var draft = NewCompanyDraft()
        XCTAssertNil(draft.usdCapMicros)
        draft.budgetInDollars = true
        draft.budgetDollars = 1_500
        XCTAssertEqual(draft.usdCapMicros, 1_500_000_000)
        draft.budgetDollars = -5
        XCTAssertEqual(draft.usdCapMicros, 0)
    }

    func testCeoShareIsPercentOfCompanyBudget() {
        var draft = NewCompanyDraft()
        draft.budgetTokens = 100_000_000
        draft.ceoBudget = Fmt.tokens(40_000_000)
        XCTAssertEqual(draft.ceoShare, 40)
        draft.budgetTokens = 20_000_000  // the CEO share is capped at the company's budget
        XCTAssertEqual(draft.ceoShare, 100)
    }
}
