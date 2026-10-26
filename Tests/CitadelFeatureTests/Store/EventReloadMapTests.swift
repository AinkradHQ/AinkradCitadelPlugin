import Foundation
import XCTest

@testable import CitadelFeature

/// Finding 19: which reads each audit event asks for (pure logic over `audited`).
@MainActor
final class EventReloadMapTests: XCTestCase {
    private func reloads(_ action: String, entity: Int64? = 7, kind: String? = nil, run: Int64? = nil) -> Set<Reload> {
        CompanyFixture.model().audited(action: action, entity: entity, kind: kind, run: run, details: [:], at: Date())
    }

    func testIssueEventsRefreshTheRequirementsTreeAndStuck() {
        let set = reloads("issue.done", kind: "issue")
        XCTAssertTrue(set.contains(.requirements))
        XCTAssertTrue(set.contains(.stuck))
    }

    func testRunEventsRefreshTheRequirementsTreeAndCosts() {
        let set = reloads("run.succeeded", entity: 9, kind: "run")
        XCTAssertTrue(set.isSuperset(of: [.requirements, .run(9), .costs]))
    }

    func testEpicAndPlanEventsRefreshTheRequirementsTree() {
        XCTAssertTrue(reloads("epic.created", kind: "epic").contains(.requirements))
        XCTAssertTrue(reloads("plan.applied", kind: "requirement").contains(.requirements))
    }

    func testRepairLeaseAndLoopBreakerEventsRefreshStuck() {
        for action in ["repair.started", "lease.expired", "loop_breaker.tripped"] {
            XCTAssertEqual(reloads(action), [.stuck], action)
        }
    }

    func testTheOpenRequirementsThreadRidesAlong() {
        let model = CompanyFixture.model()
        model.requirementsPage.selectedID = 12
        let set = model.audited(action: "issue.done", entity: 7, kind: "issue", run: nil, details: [:], at: Date())
        XCTAssertTrue(set.contains(.thread(12)))
    }

    func testRequirementEventsStillRefreshTheTree() {
        XCTAssertTrue(reloads("requirement.created", kind: "requirement").contains(.requirements))
    }
}
