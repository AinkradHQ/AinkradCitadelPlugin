import CitadelClient
import Foundation

/// The agent threads' and the approvals inbox's reads and writes (screens 06, 07).
extension CitadelServer {
    /// An issue's comments, oldest first.
    func comments(issue: Int64) async -> [CommentInfo]? {
        await read("listComments") {
            guard case .ok(let ok) = try await client.listComments(path: .init(id: issue)) else { return nil }
            return try ok.body.json.map(CommentInfo.init).sorted { $0.id < $1.id }
        }
    }

    /// Posts your comment on an issue: it answers the issue's newest open question, and wakes the agent.
    func postComment(issue: Int64, body: String, idempotencyKey: String = UUID().uuidString) async -> CommentInfo? {
        await read("postComment") {
            guard
                case .ok(let ok) = try await client.postComment(
                    path: .init(id: issue), body: .json(.init(body: body, idempotencyKey: idempotencyKey)))
            else { return nil }
            return CommentInfo(try ok.body.json.comment)
        }
    }

    /// The questions in a requirement's thread (open cards and answered receipts).
    func questions(requirement: Int64) async -> [QuestionInfo]? {
        await read("getRequirementThread") {
            guard case .ok(let ok) = try await client.getRequirementThread(path: .init(id: requirement)) else {
                return nil
            }
            return try ok.body.json.items.compactMap {
                if case .question(let item) = $0 { QuestionInfo(item.question) } else { nil }
            }
        }
    }

    /// A project's average velocity over its recent sprints.
    func velocity(project: Int64) async -> Double? {
        await read("getVelocity") {
            guard case .ok(let ok) = try await client.getVelocity(path: .init(id: project), query: .init(limit: 3))
            else { return nil }
            return try ok.body.json.average
        }
    }
}
