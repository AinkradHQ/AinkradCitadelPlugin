import CitadelClient
import Foundation

extension CitadelServer {
    /// `DELETE /accounts/{id}` (API minor 17): the account goes with its company assignments and limits. 409 while
    /// runs used it — the server's message says to disable it instead.
    func deleteAccount(_ id: Int64) async -> ServerAnswer? {
        await act { try await scoped(to: nil).client.deleteAccount(path: .init(id: id)) }
    }
}
