import CitadelClient
import Foundation

/// What the server answered when it refused an action: its status, its stable code and its message.
struct ServerAnswer: Error, Equatable, Sendable {
    var status: Int
    var code: String
    var message: String

    /// "409 conflict: Mira changed the scope 20 s ago (now 29 pts)" — what Copy error copies.
    var line: String { "\(status) \(code): \(message)" }
}

/// A server action that failed (mockup 11 G): what was tried, and the server's answer.
struct ActionFailure: Equatable, Sendable {
    /// "Couldn't approve sprint CIT S5".
    var title: String
    var answer: ServerAnswer
    /// "Nothing was approved."
    var outcome: String

    /// "The server answered 409: Mira changed the scope 20 s ago (now 29 pts). Nothing was approved."
    var message: String {
        let said =
            answer.message.isEmpty ? "" : ": \(answer.message.trimmingCharacters(in: CharacterSet(charactersIn: ".")))"
        let who = answer.status == 0 ? "The server did not answer" : "The server answered \(answer.status)"
        return "\(who)\(said). \(outcome)"
    }
}

extension CitadelServer {
    /// Approve or deny, saying why when the server refuses (`nil` = done).
    func decision(approval: Int64, approve: Bool, raiseTokens: Int64?, reply: String?) async -> ServerAnswer? {
        func refused(_ status: Int, _ body: Schemas.ErrorBody?) -> ServerAnswer {
            ServerAnswer(status: status, code: body?.code ?? "", message: body?.message ?? "")
        }
        do {
            let output = try await client.decideApproval(
                path: .init(id: approval), body: .json(.init(approve: approve, raiseTokens: raiseTokens, reply: reply)))
            switch output {
            case .ok: return nil
            case .badRequest(let r): return refused(400, try? r.body.json)
            case .unauthorized: return refused(401, nil)
            case .forbidden(let r): return refused(403, try? r.body.json)
            case .notFound(let r): return refused(404, try? r.body.json)
            case .conflict(let r): return refused(409, try? r.body.json)
            case .tooManyRequests: return refused(429, nil)
            case .internalServerError(let r): return refused(500, try? r.body.json)
            case .undocumented(let status, _): return refused(status, nil)
            }
        } catch {
            return ServerAnswer(status: 0, code: "unreachable", message: error.localizedDescription)
        }
    }
}
