import CitadelClient
import Foundation

/// Accounts writes the screen wires beyond the pool reads: pause / resume.
extension CitadelServer {
    /// Pauses (`disabled`) or resumes (`active`) an account: running work finishes, nothing new starts on it.
    func setAccountStatus(_ account: Int64, paused: Bool, reason: String?) async -> Result<PoolAccount, ServerAnswer> {
        let word = paused ? "disabled" : "active"
        return await attempt({
            try await scoped(to: nil).client.setAccountStatus(
                path: .init(id: account),
                body: .json(
                    .init(reason: reason, status: .init(value1: .init(rawValue: word), value2: word))))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            return PoolAccount(try ok.body.json, usage: nil)
        }
    }
}
