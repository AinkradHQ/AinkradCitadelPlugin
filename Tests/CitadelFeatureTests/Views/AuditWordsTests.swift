import XCTest

@testable import CitadelFeature

final class AuditWordsTests: XCTestCase {
    func testKnownActionsReadAsWords() {
        XCTAssertEqual(AuditWords.plain("device.revoked"), "revoked a device key")
        XCTAssertEqual(AuditWords.plain("approval.approved"), "approved a request")
    }

    func testUnknownActionsFallBackToSpacedWords() {
        XCTAssertEqual(AuditWords.plain("issue.state_changed"), "issue state changed")
    }
}
