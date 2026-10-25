import CitadelClient
import Foundation

/// API minor 18: an issue's own fields and its activity, and an epic's look and dates.
extension CitadelServer {
    /// `PATCH /issues/{id}`: only the fields `patch` names change; the issue as the server keeps it.
    func updateIssue(_ issue: Int64, _ patch: Schemas.IssuePatch) async -> Result<WorkItem, ServerAnswer> {
        await attempt({ try await client.updateIssue(path: .init(id: issue), body: .json(patch)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return WorkItem(try ok.body.json)
        }
    }

    /// What was done to an issue, newest first (`GET /issues/{id}/activity`).
    func issueActivityLog(_ issue: Int64, limit: Int32 = 12) async -> [AuditLine]? {
        await read("listIssueActivity") {
            guard
                case .ok(let ok) = try await client.listIssueActivity(
                    path: .init(id: issue), query: .init(limit: limit))
            else { return nil }
            return try ok.body.json.items.map(AuditLine.init)
        }
    }

    /// `PATCH /epics/{id}`.
    func updateEpic(_ epic: Int64, _ patch: Schemas.EpicPatch) async -> Result<EpicInfo, ServerAnswer> {
        await attempt({ try await client.updateEpic(path: .init(id: epic), body: .json(patch)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return EpicInfo(try ok.body.json)
        }
    }
}
