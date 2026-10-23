import AppKit
import Foundation
import UniformTypeIdentifiers

/// Cost (09) and Why stuck (08): the period's reads and the fixes a stuck card sends.
extension CitadelStore {
    /// Loads a period: its issues, this company's account use, its spend by agent and department, and one bar per
    /// day (at least the last 7 days; per hour on Today) from the server's spend series.
    func loadCost(_ period: CostPeriod, now: Date = Date()) {
        guard let server, let model else { return }
        model.costPeriod = period
        let start = period.start(now: now, sprintStart: model.sprint?.startsOn)
        let first = period.chartStart(now: now, start: start)
        let company = model.companyID
        Task {
            async let tasks = server.taskCosts(company: company, since: start)
            async let use = server.accountUse(company: company)
            async let breakdown = server.spendBreakdown(company: company, since: start)
            async let days = server.spendSeries(company: company, bucket: period == .today ? "hour" : "day", since: first)
            guard model.costPeriod == period else { return }
            if let tasks = await tasks { model.costTasks = tasks }
            if let use = await use { model.accountUse = use }
            if let (agents, departments) = await breakdown {
                model.costByAgent = agents
                model.costByDepartment = departments
            }
            if let days = await days { model.costDays = days }
        }
    }

    /// The period read again after a run or budget event: its issues, breakdown and bars.
    func refreshCostTasks(_ model: CompanyModel, server: CitadelServer) async {
        guard let period = model.costPeriod else { return }
        let start = period.start(sprintStart: model.sprint?.startsOn)
        if let tasks = await server.taskCosts(company: model.companyID, since: start) { model.costTasks = tasks }
        if let (agents, departments) = await server.spendBreakdown(company: model.companyID, since: start) {
            model.costByAgent = agents
            model.costByDepartment = departments
        }
        let first = period.chartStart(now: Date(), start: start)
        if let days = await server.spendSeries(
            company: model.companyID, bucket: period == .today ? "hour" : "day", since: first)
        {
            model.costDays = days
        }
    }

    /// A stuck card's fix: hand the issue to an agent, which is woken. The card goes when the engine's next
    /// `.stuck` read says so.
    func reassign(_ stuck: StuckInfo, to agent: Int64) {
        guard let issue = stuck.issueID else { return }
        let name = model?.agent(agent)?.name ?? "the agent"
        act("Couldn't reassign \(key(issue)) to \(name)", outcome: "It still waits where it was.", issue: issue) {
            await $0.reassignIssue(issue, to: agent)
        }
    }

    func unblock(_ stuck: StuckInfo) {
        guard let server, let issue = stuck.issueID else { return }
        Task { if await server.unblock(issue: issue) { schedule([.stuck, .issueFresh(issue)]) } }
    }

    /// The engine's `rewake` / `requeue`, by hand: its next actor woken again.
    func nudge(_ stuck: StuckInfo) {
        guard let issue = stuck.issueID else { return }
        act("Couldn't wake \(key(issue))'s agent", outcome: "Nobody was woken.", issue: issue) { await $0.nudge(issue: issue) }
    }

    /// Sets the issue aside in the backlog, waiting on you.
    func moveToBacklog(_ stuck: StuckInfo) {
        guard let issue = stuck.issueID else { return }
        act("Couldn't move \(key(issue)) to the backlog", outcome: "It stays where it was.", issue: issue) {
            await $0.moveToBacklog(issue: issue)
        }
    }

    /// "Wake my Mac" (`now`) / "Run when I'm back" (`when_back`): the sleeping runner that has the tags the
    /// waiting agent needs.
    func wakeRunner(for stuck: StuckInfo, when: String) {
        guard let server, let model else { return }
        let tags = model.agent(stuck.agentID)?.runnerTags ?? []
        Task {
            guard let runner = sleepingRunner(for: tags, in: await server.runnerList() ?? []) else {
                actionFailure = ActionFailure(
                    title: "No runner to wake",
                    answer: ServerAnswer(
                        status: 404, code: "not_found",
                        message: "no offline runner has the tags \(tags.joined(separator: ", "))"),
                    outcome: "Nothing was sent.")
                return
            }
            if let answer = await server.wake(runner: runner.id, when: when) {
                actionFailure = ActionFailure(
                    title: "Couldn't wake \(runner.name)", answer: answer, outcome: "Nothing was sent.")
            } else {
                schedule([.stuck, .runners])
            }
        }
    }

    /// "Set a price…": the model's price from now on; runs before stay unpriced.
    func setPrice(_ price: PriceDraft) {
        act("Couldn't set the price of \(price.model)", outcome: "No price was set.") { await $0.setPrice(price) }
    }

    /// A budget's cap (tokens, raises included as shown) and warn % (`nil` inherits).
    func setBudget(_ budget: BudgetInfo, cap: Int64, warnPercent: Int?) {
        guard let company = model?.companyID else { return }
        act("Couldn't change the \(budget.label) budget", outcome: "The budget is unchanged.") {
            await $0.setBudget(company: company, budget, cap: cap, warnPercent: warnPercent)
        }
    }

    private func key(_ issue: Int64) -> String { model?.issue(issue)?.key ?? "the issue" }

    /// Sends an action; a refusal becomes the 11 G banner, success asks for the reads its event will also ask for.
    private func act(
        _ title: String, outcome: String, issue: Int64? = nil, _ send: @escaping (CitadelServer) async -> ServerAnswer?
    ) {
        guard let server else { return }
        Task {
            if let answer = await send(server) {
                actionFailure = ActionFailure(title: title, answer: answer, outcome: outcome)
            } else {
                actionFailure = nil
                schedule(issue.map { [.stuck, .costs, .issueFresh($0)] } ?? [.costs])
            }
        }
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

/// The sleeping (offline) runner that can take work needing `tags`: one with every tag, else none.
func sleepingRunner(for tags: [String], in runners: [RunnerInfo]) -> RunnerInfo? {
    runners.first { $0.status == "offline" && Set(tags).isSubset(of: $0.tags) }
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
