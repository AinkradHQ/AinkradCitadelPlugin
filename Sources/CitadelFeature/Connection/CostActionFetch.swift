import CitadelClient
import Foundation

/// Why stuck (08) and Cost (09): the spend series and breakdown, and the actions their cards send — nudge, back
/// to the backlog, wake a runner, a price, a budget cap. An action returns `nil` when done, else the server's
/// refusal (mockup 11 G).
extension CitadelServer {
    /// The company's spend per `bucket` (`hour` or `day`) from `since`, oldest first, every bucket present.
    func spendSeries(company: Int64, bucket: String, since: Date) async -> [DaySpend]? {
        await read("getSpendSeries") {
            let query = Operations.GetSpendSeries.Input.Query(bucket: bucket, since: since.formatted(.iso8601))
            guard case .ok(let ok) = try await client.getSpendSeries(path: .init(id: company), query: query)
            else { return nil }
            return try ok.body.json.map { DaySpend(day: $0.start, totals: SpendTotals($0.spend)) }
        }
    }

    /// The company's spend from `since` by agent and by department.
    func spendBreakdown(company: Int64, since: Date?) async -> (agents: [ScopeSpend], departments: [ScopeSpend])? {
        await read("getSpendBreakdown") {
            let query = Operations.GetSpendBreakdown.Input.Query(since: since?.formatted(.iso8601))
            guard case .ok(let ok) = try await client.getSpendBreakdown(path: .init(id: company), query: query)
            else { return nil }
            let breakdown = try ok.body.json
            return (
                breakdown.agents.map { ScopeSpend(id: $0.agentId, totals: SpendTotals($0.spend)) },
                breakdown.departments.map { ScopeSpend(id: $0.departmentId, totals: SpendTotals($0.spend)) }
            )
        }
    }

    /// Wakes the issue's next actor again (the engine's `rewake` / `requeue`, by hand).
    func nudge(issue: Int64) async -> ServerAnswer? {
        await act { try await client.nudgeIssue(path: .init(id: issue)) }
    }

    /// Hands the issue to an agent, which is woken.
    func reassignIssue(_ issue: Int64, to agent: Int64) async -> ServerAnswer? {
        await act { try await client.reassignIssue(path: .init(id: issue), body: .json(.init(agentId: agent))) }
    }

    /// Sets the issue aside in the backlog, waiting on you; nobody is woken.
    func moveToBacklog(issue: Int64) async -> ServerAnswer? {
        await act { try await client.moveToBacklog(path: .init(id: issue)) }
    }

    /// A model's price from now on, dollars per million tokens.
    func setPrice(_ price: PriceDraft) async -> ServerAnswer? {
        await act {
            try await client.setPrice(
                body: .json(
                    .init(
                        cacheUsdPerMtok: price.cache, harness: .init(value1: .init(rawValue: price.harness)),
                        inputUsdPerMtok: price.input, model: price.model, outputUsdPerMtok: price.output)))
        }
    }

    /// Creates or changes the budget for a scope and period: its cap (tokens, the raises excluded) and its warn %
    /// (`nil` inherits `budget.warn_percent`).
    func setBudget(company: Int64, _ budget: BudgetInfo, cap: Int64, warnPercent: Int?) async -> ServerAnswer? {
        guard let scope = BudgetInfo.wireScope(budget.scope) else {
            return ServerAnswer(status: 400, code: "bad_scope", message: "Unknown budget scope \(budget.scope)")
        }
        let known = Schemas.BudgetPeriod.Value1Payload(rawValue: budget.period)
        let period = Schemas.BudgetPeriod(value1: known, value2: known == nil ? budget.period : nil)
        return await act {
            try await client.setBudget(
                path: .init(id: company),
                body: .json(
                    .init(
                        hardStop: budget.hardStop, period: period, scope: scope, tokenCap: max(0, cap - budget.raised),
                        warnAtPercent: warnPercent.map(Int32.init))))
        }
    }

    /// Runs a generated call: `nil` when it answered 200, else its refusal.
    private func act(_ call: () async throws -> some Sendable) async -> ServerAnswer? {
        do {
            return Self.refusal(try await call())
        } catch {
            return ServerAnswer(status: 0, code: "unreachable", message: error.localizedDescription)
        }
    }
}

extension BudgetInfo {
    /// `agent:3`, `company:1`, … as the wire's budget scope.
    static func wireScope(_ scope: String) -> Schemas.BudgetScope? {
        let parts = scope.split(separator: ":")
        guard parts.count == 2, let id = Int64(parts[1]) else { return nil }
        switch parts[0] {
        case "company": return .company(.init(companyId: id, kind: .company))
        case "department": return .department(.init(departmentId: id, kind: .department))
        case "project": return .project(.init(kind: .project, projectId: id))
        case "agent": return .agent(.init(agentId: id, kind: .agent))
        case "sprint": return .sprint(.init(kind: .sprint, sprintId: id))
        default: return nil
        }
    }
}

extension SpendTotals {
    init(_ spend: Schemas.Spend) {
        self.init(
            costMicros: spend.costUsdMicros, pricedTokens: spend.pricedTokens, unpricedTokens: spend.unpricedTokens,
            subscriptionTokens: spend.subscriptionTokens, unpricedRuns: spend.unpricedRuns,
            subscriptionRuns: spend.subscriptionRuns)
    }
}
