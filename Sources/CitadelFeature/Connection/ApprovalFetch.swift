import CitadelClient
import Foundation

/// The approvals stage's extra reads (screen 06): a sprint's velocity series and a merge's worktree diff.
extension CitadelServer {
    /// A project's last 3 closed sprints: their mean and each one's completed points, oldest first.
    func velocityPoints(project: Int64) async -> (average: Double, completed: [Int])? {
        await read("getVelocity") {
            guard case .ok(let ok) = try await client.getVelocity(path: .init(id: project), query: .init(limit: 3))
            else { return nil }
            let body = try ok.body.json
            return (body.average, body.sprints.reversed().map { Int($0.completed) })
        }
    }

    /// An issue's worktrees against their base, per repo, as its latest run measured them.
    func issueDiff(_ issue: Int64) async -> [RepoDiffInfo]? {
        await read("getIssueDiff") {
            guard case .ok(let ok) = try await client.getIssueDiff(path: .init(id: issue)) else { return nil }
            return try ok.body.json.repos.map(RepoDiffInfo.init)
        }
    }
}
