import AinkradAppKit
import XCTest

@testable import CitadelFeature

/// Scoped settings (decision #52): values in their units, typed input, bounds, and the scope chip.
final class ScopedSettingTests: XCTestCase {
    private func stall(value: Int64 = 900, source: String? = nil) -> ScopedSetting {
        ScopedSetting(
            key: "run.stall_after_secs", description: "", value: value, defaultValue: 900, min: 60, max: 7_200,
            unit: "seconds", scopes: ["server", "company", "project"], source: source)
    }

    func testValuesReadInTheirUnits() {
        XCTAssertEqual(stall().text, "15 min")
        XCTAssertEqual(stall().bounds, "1 min–2 h")
        XCTAssertEqual(ScopedSetting.format(50_000_000_000, unit: "bytes"), "50 GB")
        XCTAssertEqual(ScopedSetting.format(200_000, unit: "tokens"), "200k")
        XCTAssertEqual(ScopedSetting.format(86_400, unit: "seconds"), "1 d")
        XCTAssertEqual(ScopedSetting.format(80, unit: "percent"), "80%")
    }

    func testTypedValuesParseAndOutOfBoundsIsRefused() {
        XCTAssertEqual(stall().parse("10 min"), 600)
        XCTAssertEqual(stall().parse("2h"), 7_200)
        XCTAssertEqual(ScopedSetting.parse("900 GB", unit: "bytes"), 900_000_000_000)
        XCTAssertEqual(ScopedSetting.parse("200k", unit: "tokens"), 200_000)
        XCTAssertNil(stall().parse("ten"))
        XCTAssertTrue(stall().accepts("10 min"))
        XCTAssertFalse(stall().accepts("3 h"), "past the 2 h maximum")
        XCTAssertFalse(stall().accepts("30 s"), "under the 1 min minimum")
    }

    func testTheChipSaysWhereTheValueComesFrom() {
        XCTAssertEqual(stall().chip(at: "company:1"), .inherited(from: "server"))
        XCTAssertEqual(stall(source: "company:1").chip(at: "project:2"), .inherited(from: "company"))
        XCTAssertEqual(
            stall(value: 600, source: "project:2").chip(at: "project:2", inherited: stall(source: "company:1")),
            .overridden(at: "project", inheritedValue: "company 15 min"))
        XCTAssertEqual(
            stall(value: 600, source: "company:1").chip(at: "company:1"),
            .overridden(at: "company", inheritedValue: nil))
    }
}
