import AinkradAppKit
import Foundation

extension CitadelStore {
    /// Removes an account from the pool (the card's confirmed Remove). A refusal — 409 when runs used it — shows the
    /// server's own message as the failure toast; an older server never gets the call.
    func removeAccount(_ account: PoolAccount) {
        guard serverSupports(minor: Self.structureMinor), let server, let page = model?.accountsPage else { return }
        Task {
            if let answer = await server.deleteAccount(account.id) {
                toast(
                    AinkradRichToast(
                        title: "Couldn't remove \(account.label)",
                        body: answer.message.isEmpty ? answer.line : answer.message, status: .danger))
                return
            }
            page.accounts.removeAll { $0.id == account.id }
            toast(
                AinkradRichToast(
                    title: "\(account.label) removed", body: "Its assignments and limits went with it.",
                    status: .warning))
            schedule([.accounts])
            loadAccountsPage()
        }
    }
}
