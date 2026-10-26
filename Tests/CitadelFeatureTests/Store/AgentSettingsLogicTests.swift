import Foundation
import XCTest

@testable import CitadelFeature

/// The apply-on-pick model edit and the hire request's age.
@MainActor
final class AgentSettingsLogicTests: XCTestCase {
    private let agent = CompanyFixture.agent(1, "Kestrel", role: "Dev", model: "sonnet-5", palette: "ultraviolet")

    func testNothingChangedSendsNothing() {
        XCTAssertNil(DrawerSettings.modelPatch(harness: "claude", wire: "sonnet-5", effort: "medium", agent: agent))
    }

    func testEffortAloneSends() {
        XCTAssertNotNil(DrawerSettings.modelPatch(harness: "claude", wire: "sonnet-5", effort: "high", agent: agent))
    }

    func testNewHarnessWaitsForItsOwnModel() {
        XCTAssertNil(DrawerSettings.modelPatch(harness: "codex", wire: "sonnet-5", effort: "medium", agent: agent))
        let wire = HireCatalog.models["codex"]?.first?.wire ?? ""
        XCTAssertEqual(
            DrawerSettings.modelPatch(harness: "codex", wire: wire, effort: "medium", agent: agent)?.harness, "codex")
    }

    func testHireAgeSuffix() {
        let now = Date()
        XCTAssertEqual(OrgPeekPanel.ageSuffix(now.addingTimeInterval(-7_200), now: now), " · 2h ago")
        XCTAssertEqual(OrgPeekPanel.ageSuffix(nil), "")
    }
}
