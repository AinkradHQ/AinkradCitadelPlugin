import Foundation
import XCTest

@testable import CitadelFeature

/// API minor 17, accounts: DELETE /accounts/{id} and its 409.
@MainActor
final class WireSeventeenAccountsTests: XCTestCase {
    private func store(minor: Int? = 17) throws -> (CitadelStore, PoolAccount) {
        let store = try Wire17.store(minor: minor)
        let model = try XCTUnwrap(store.model)
        CompanyFixture.accountsParityPage(model)
        return (store, try XCTUnwrap(model.accountsPage.accounts.first))
    }

    func testRemovingAnAccountDeletesItAndDropsItFromThePage() async throws {
        let (store, account) = try store()
        FakeServer.serve { _ in .init(json: #"{"id":1}"#) }
        store.removeAccount(account)
        _ = try await Wire17.sent("DELETE", "/api/v1/accounts/\(account.id)")
        await eventually { store.model?.accountsPage.accounts.contains { $0.id == account.id } == false }
        XCTAssertEqual(store.toasts.items.first?.title, "\(account.label) removed")
    }

    func testAnAccountRunsUsedIsKeptAndTheServersMessageIsTheToast() async throws {
        let (store, account) = try store()
        FakeServer.serve { _ in
            .init(status: 409, json: Wire.refusal("conflict", "used by runs — disable it instead"))
        }
        store.removeAccount(account)
        await eventually { store.toasts.items.first != nil }
        XCTAssertEqual(store.toasts.items.first?.body, "used by runs — disable it instead")
        XCTAssertTrue(store.model?.accountsPage.accounts.contains { $0.id == account.id } == true)
    }

    func testAnOlderServerIsNeverAskedToDeleteAnAccount() async throws {
        let (store, account) = try store(minor: 16)
        FakeServer.serve { _ in .init(status: 404, json: Wire.refusal("not_found", "no route")) }
        store.removeAccount(account)
        try await Task.sleep(for: .milliseconds(200))
        XCTAssertFalse(Wire17.didSend("DELETE", "/api/v1/accounts/\(account.id)"))
        XCTAssertTrue(store.toasts.items.isEmpty)
    }
}
