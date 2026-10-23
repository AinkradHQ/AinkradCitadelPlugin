import CitadelClient
import Foundation

/// A refusal's body, whichever error response carries it.
private protocol CarriesErrorBody { var errorBody: Schemas.ErrorBody? { get } }
extension Components.Responses.BadRequest: CarriesErrorBody { var errorBody: Schemas.ErrorBody? { try? body.json } }
extension Components.Responses.Unauthorized: CarriesErrorBody { var errorBody: Schemas.ErrorBody? { try? body.json } }
extension Components.Responses.Forbidden: CarriesErrorBody { var errorBody: Schemas.ErrorBody? { try? body.json } }
extension Components.Responses.NotFound: CarriesErrorBody { var errorBody: Schemas.ErrorBody? { try? body.json } }
extension Components.Responses.Conflict: CarriesErrorBody { var errorBody: Schemas.ErrorBody? { try? body.json } }
extension Components.Responses.TooManyRequests: CarriesErrorBody {
    var errorBody: Schemas.ErrorBody? { try? body.json }
}
extension Components.Responses.InternalError: CarriesErrorBody { var errorBody: Schemas.ErrorBody? { try? body.json } }

/// The run and agent controls of screens 02–07 (pause, resume, stop, message, allow for an issue) and the reads
/// that came with them (open questions, an issue's diff). Each action returns `nil` when done, else the server's
/// answer for the 11 G error state.
extension CitadelServer {
    /// Every generated operation's output has the same cases (`ok`, `badRequest`, …, `undocumented`), so one reading
    /// of the case name covers them all: `nil` for `ok`, else the status and the server's code and message.
    static func refusal(_ output: Any) -> ServerAnswer? {
        let statuses = [
            "badRequest": 400, "unauthorized": 401, "forbidden": 403, "notFound": 404, "conflict": 409,
            "tooManyRequests": 429, "internalServerError": 500,
        ]
        guard let child = Mirror(reflecting: output).children.first, let label = child.label else {
            return ServerAnswer(status: 0, code: "unknown", message: "")
        }
        if label == "ok" { return nil }
        if label == "undocumented", let status = Mirror(reflecting: child.value).children.first?.value as? Int {
            return ServerAnswer(status: status, code: "", message: "")
        }
        let body = (child.value as? CarriesErrorBody)?.errorBody
        return ServerAnswer(status: statuses[label] ?? 0, code: body?.code ?? "", message: body?.message ?? "")
    }

    private func act(_ work: () async throws -> Any) async -> ServerAnswer? {
        do {
            return Self.refusal(try await work())
        } catch {
            return ServerAnswer(status: 0, code: "unreachable", message: error.localizedDescription)
        }
    }

    func pause(agent: Int64) async -> ServerAnswer? {
        await act { try await client.pauseAgent(path: .init(id: agent)) }
    }

    func resume(agent: Int64) async -> ServerAnswer? {
        await act { try await client.resumeAgent(path: .init(id: agent)) }
    }

    func pause(company: Int64) async -> ServerAnswer? {
        await act { try await client.pauseCompany(path: .init(id: company)) }
    }

    func resume(company: Int64) async -> ServerAnswer? {
        await act { try await client.resumeCompany(path: .init(id: company)) }
    }

    /// Ends the run now (`cancelled`, "stopped by admin"); its runner kills the harness.
    func stop(run: Int64) async -> ServerAnswer? {
        await act { try await client.stopRun(path: .init(id: run)) }
    }

    /// A message the running agent gets at its next turn, without stopping it.
    func message(run: Int64, body: String, idempotencyKey: String = UUID().uuidString) async -> ServerAnswer? {
        await act {
            try await client.messageRun(
                path: .init(id: run), body: .json(.init(body: body, idempotencyKey: idempotencyKey)))
        }
    }

    /// Approves the permission escalation and lets the same call go ahead on its issue's runs for a while.
    func allowForIssue(approval: Int64, reply: String?) async -> ServerAnswer? {
        await act { try await client.allowForIssue(path: .init(id: approval), body: .json(.init(reply: reply))) }
    }

    /// The company's open agent questions, from every issue (not only the requirements').
    func openQuestions(company: Int64) async -> [QuestionInfo]? {
        await read("listOpenQuestions") {
            guard case .ok(let ok) = try await client.listOpenQuestions(path: .init(id: company)) else { return nil }
            return try ok.body.json.map(QuestionInfo.init)
        }
    }
}

/// One repo's diff of an issue's worktree: the run rail's `+38 −6`.
struct RepoDiffInfo: Equatable, Sendable {
    var repo: String
    var files: Int64
    var insertions: Int64
    var deletions: Int64

    init(repo: String, files: Int64, insertions: Int64, deletions: Int64) {
        self.repo = repo
        self.files = files
        self.insertions = insertions
        self.deletions = deletions
    }

    init(_ diff: Schemas.RepoDiff) {
        self.init(
            repo: diff.repo, files: Int64(diff.files), insertions: Int64(diff.insertions),
            deletions: Int64(diff.deletions))
    }
}
