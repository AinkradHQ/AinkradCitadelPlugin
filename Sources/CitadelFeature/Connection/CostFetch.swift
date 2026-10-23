import CitadelClient
import Foundation

/// The Cost (09) and Why stuck (08) screens' reads and the issue transitions their fixes send.
extension CitadelServer {
    /// Each issue's spend from runs queued at or after `since`.
    func taskCosts(company: Int64, since: Date?) async -> [TaskCostInfo]? {
        await read("getTaskCosts") {
            let query = Operations.GetTaskCosts.Input.Query(since: since?.formatted(.iso8601))
            guard case .ok(let ok) = try await client.getTaskCosts(path: .init(id: company), query: query)
            else { return nil }
            return try ok.body.json.map {
                TaskCostInfo(
                    issueID: $0.issueId, key: $0.key, title: $0.title,
                    tokens: $0.inputTokens + $0.outputTokens + $0.cacheTokens, unpricedTokens: $0.unpricedTokens,
                    subscriptionTokens: $0.subscriptionTokens, costMicros: $0.costUsdMicros, secs: $0.secs,
                    runs: $0.runs, pricedRuns: $0.pricedRuns, unpricedRuns: $0.unpricedRuns,
                    subscriptionRuns: $0.subscriptionRuns)
            }
        }
    }

    /// This company's use of each pool account.
    func accountUse(company: Int64) async -> [AccountUseInfo]? {
        await read("companyAccountUsage") {
            guard case .ok(let ok) = try await client.companyAccountUsage(path: .init(id: company)) else { return nil }
            return try ok.body.json.map {
                AccountUseInfo(id: $0.accountId, label: $0.label, tokens: $0.tokens, runs: $0.runs)
            }
        }
    }

    /// Unblocks a blocked issue.
    func unblock(issue: Int64) async -> Bool {
        await transition(issue, .unblock(.init(kind: .unblock)))
    }

    private func transition(_ issue: Int64, _ body: Schemas.Transition) async -> Bool {
        await read("transitionIssue") {
            guard case .ok = try await client.transitionIssue(path: .init(id: issue), body: .json(body)) else {
                return false
            }
            return true
        } ?? false
    }
}
