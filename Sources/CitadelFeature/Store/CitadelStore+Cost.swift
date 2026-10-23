import AppKit
import Foundation
import UniformTypeIdentifiers

/// Cost (09) and Why stuck (08): the period's reads and the fixes a stuck card sends.
extension CitadelStore {
    /// Loads a period: its issues, this company's account use, and one day per bar (at least the last 7 days).
    func loadCost(_ period: CostPeriod, now: Date = Date()) {
        guard let server, let model else { return }
        model.costPeriod = period
        let calendar = Calendar.current
        let start = period.start(now: now, sprintStart: model.sprint?.startsOn)
        let today = calendar.startOfDay(for: now)
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        let first = min(start ?? weekAgo, weekAgo)
        let days = stride(
            from: 0, through: max(0, calendar.dateComponents([.day], from: first, to: today).day ?? 0), by: 1
        )
        .compactMap { calendar.date(byAdding: .day, value: $0, to: first) }
        let company = model.companyID
        Task {
            async let tasks = server.taskCosts(company: company, since: start)
            async let use = server.accountUse(company: company)
            // ponytail: one "since" read per day (≤ 31) until the server serves a daily series (hourly spend is
            // coming with the action endpoints); each day is its sum less the next day's.
            let cumulative = await withTaskGroup(of: (Date, SpendTotals?).self) { group in
                for day in days {
                    group.addTask { (day, await server.taskCosts(company: company, since: day).map(SpendTotals.init)) }
                }
                var out: [(day: Date, totals: SpendTotals)] = []
                for await (day, totals) in group { if let totals { out.append((day, totals)) } }
                return out.sorted { $0.day < $1.day }
            }
            guard model.costPeriod == period else { return }
            if let tasks = await tasks { model.costTasks = tasks }
            if let use = await use { model.accountUse = use }
            model.costDays = daySpends(cumulative: cumulative)
        }
    }

    /// The period's issues read again after a run or budget event (the day bars wait for the next period load).
    func refreshCostTasks(_ model: CompanyModel, server: CitadelServer) async {
        guard let period = model.costPeriod else { return }
        let start = period.start(sprintStart: model.sprint?.startsOn)
        if let tasks = await server.taskCosts(company: model.companyID, since: start) { model.costTasks = tasks }
    }

    /// A stuck card's fix: hand the issue to an agent. The card goes when the engine's next `.stuck` read says so.
    func reassign(_ stuck: StuckInfo, to agent: Int64) {
        guard let server, let issue = stuck.issueID else { return }
        Task { if await server.reassign(issue: issue, to: agent) { schedule([.stuck, .issueFresh(issue)]) } }
    }

    func unblock(_ stuck: StuckInfo) {
        guard let server, let issue = stuck.issueID else { return }
        Task { if await server.unblock(issue: issue) { schedule([.stuck, .issueFresh(issue)]) } }
    }

    /// Export CSV: the period's per-task rows.
    func exportCostCSV() {
        guard let model else { return }
        let panel = NSSavePanel()
        panel.allowedContentTypes = [.commaSeparatedText]
        panel.nameFieldStringValue = "citadel-cost-\(model.costPeriod?.rawValue ?? "period").csv"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        try? Data(costCSV(model.costTasks).utf8).write(to: url)
    }
}

/// `issue,title,tokens,priced_tokens,unpriced_tokens,subscription_tokens,usd,seconds,runs`, one row per issue.
func costCSV(_ tasks: [TaskCostInfo]) -> String {
    func field(_ text: String) -> String {
        text.contains { [",", "\"", "\n"].contains($0) }
            ? "\"\(text.replacingOccurrences(of: "\"", with: "\"\""))\"" : text
    }
    let head = "issue,title,tokens,priced_tokens,unpriced_tokens,subscription_tokens,usd,seconds,runs"
    let rows = tasks.map { t in
        [
            t.key, field(t.title), "\(t.tokens)", "\(t.pricedTokens)", "\(t.unpricedTokens)", "\(t.subscriptionTokens)",
            String(format: "%.2f", Double(t.costMicros) / 1_000_000), "\(t.secs)", "\(t.runs)",
        ].joined(separator: ",")
    }
    return ([head] + rows).joined(separator: "\n") + "\n"
}
