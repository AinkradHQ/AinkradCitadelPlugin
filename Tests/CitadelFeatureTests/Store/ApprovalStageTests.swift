import Foundation
import XCTest

@testable import CitadelFeature

/// Screen 06's stage: what "This project" saves, whom a reply wakes, the type families and the runs it holds.
@MainActor
final class ApprovalStageTests: XCTestCase {
    func testThePrototypeInboxReadsAsThePrototype() {
        let model = CompanyFixture.model()
        CompanyFixture.approvalsProto(model)
        let permission = model.approvals[0]
        XCTAssertEqual(PermissionAsk(permission.fields).rule, "Bash:cargo add")
        XCTAssertEqual(model.summary(permission).title, "Kestrel wants to run cargo add")
        XCTAssertEqual(model.approvals.filter(model.holdsRun).count, 2)

        // A hire's agent is not seated yet: its proposer hears the reply.
        let hire = model.approvals[4]
        XCTAssertEqual(model.replyTarget(hire), "Nadia")
        XCTAssertEqual(model.involved(hire).map(\.name), ["Nadia"])
        XCTAssertEqual(model.teamPath(of: hire.agentID), "Marketing › Launch")

        XCTAssertEqual(model.approvals.map { ApprovalFilter.of($0) }, [.permission, .budget, .sprint, .merge, .hire])
        XCTAssertEqual(PermissionAsk(["tool": "Edit"]).rule, "Edit")
    }
}
