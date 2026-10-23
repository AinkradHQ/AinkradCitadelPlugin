import AinkradAppKit
import Foundation

/// The Cost screen's period switch (screen 09): Today, this week, this month, the active sprint.
enum CostPeriod: String, CaseIterable, Hashable {
    case today, week, month, sprint

    var title: String { rawValue.prefix(1).uppercased() + rawValue.dropFirst() }

    /// Where the period starts; `nil` for Sprint with no active sprint.
    func start(now: Date = Date(), sprintStart: Date?, calendar: Calendar = .current) -> Date? {
        switch self {
        case .today: calendar.startOfDay(for: now)
        case .week: calendar.dateInterval(of: .weekOfYear, for: now)?.start
        case .month: calendar.dateInterval(of: .month, for: now)?.start
        case .sprint: sprintStart.map { calendar.startOfDay(for: $0) }
        }
    }

    /// Where the chart starts: the period's start, but at least the last 7 days (Today: its hours).
    func chartStart(now: Date, start: Date?, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        if self == .today { return today }
        let weekAgo = calendar.date(byAdding: .day, value: -6, to: today) ?? today
        return min(start ?? weekAgo, weekAgo)
    }
}

/// One issue's spend in the period (`getTaskCosts`): tokens by kind, dollars of its priced runs only, wall time.
struct TaskCostInfo: Identifiable, Equatable, Sendable {
    var id: Int64 { issueID }
    let issueID: Int64
    var key: String
    var title: String
    var tokens: Int64
    var unpricedTokens: Int64
    var subscriptionTokens: Int64
    var costMicros: Int64
    var secs: Int64
    var runs: Int64
    var pricedRuns: Int64
    var unpricedRuns: Int64
    var subscriptionRuns: Int64

    var pricedTokens: Int64 { max(0, tokens - unpricedTokens - subscriptionTokens) }
    /// The project key, `CIT` of `CIT-42`.
    var projectKey: String { key.split(separator: "-").first.map(String.init) ?? key }

    /// "$1.90", "sub" (subscription only), or "unpriced" — never "$0" for a run with no price.
    var dollarsWord: String {
        if pricedRuns > 0 { return Fmt.dollars(micros: costMicros) }
        if unpricedRuns > 0 { return "unpriced" }
        return subscriptionRuns > 0 ? "sub" : Fmt.dollars(micros: 0)
    }
}

/// What this company used of one pool account (decision #41: never another company's share).
struct AccountUseInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var label: String
    var tokens: Int64
    var runs: Int64
}

/// A period's spend added up from its issues.
struct SpendTotals: Equatable, Sendable {
    var costMicros: Int64 = 0
    var pricedTokens: Int64 = 0
    var unpricedTokens: Int64 = 0
    var subscriptionTokens: Int64 = 0
    var unpricedRuns: Int64 = 0
    var subscriptionRuns: Int64 = 0

    init(
        costMicros: Int64 = 0, pricedTokens: Int64 = 0, unpricedTokens: Int64 = 0, subscriptionTokens: Int64 = 0,
        unpricedRuns: Int64 = 0, subscriptionRuns: Int64 = 0
    ) {
        self.costMicros = costMicros
        self.pricedTokens = pricedTokens
        self.unpricedTokens = unpricedTokens
        self.subscriptionTokens = subscriptionTokens
        self.unpricedRuns = unpricedRuns
        self.subscriptionRuns = subscriptionRuns
    }

    init(_ tasks: [TaskCostInfo]) {
        for task in tasks {
            costMicros += task.costMicros
            pricedTokens += task.pricedTokens
            unpricedTokens += task.unpricedTokens
            subscriptionTokens += task.subscriptionTokens
            unpricedRuns += task.unpricedRuns
            subscriptionRuns += task.subscriptionRuns
        }
    }

    /// Every token, whatever its kind: what the breakdown bars compare.
    var tokens: Int64 { pricedTokens + unpricedTokens + subscriptionTokens }

    var spend: SpendInfo {
        SpendInfo(
            costMicros: costMicros, runs: 0, pricedRuns: 0, unpricedRuns: unpricedRuns, unpricedTokens: unpricedTokens,
            subscriptionRuns: subscriptionRuns, subscriptionTokens: subscriptionTokens, pricedTokens: pricedTokens)
    }
}

/// One agent's or department's spend in the period (`getSpendBreakdown`); a department `nil` is work outside any.
struct ScopeSpend: Equatable, Sendable {
    var id: Int64?
    var totals: SpendTotals
}

/// "Set a price…": a model's dollars per million tokens, checked before it is sent.
struct PriceDraft: Equatable, Sendable {
    var harness: String
    var model: String
    var input: Double
    var output: Double
    var cache: Double

    static let harnesses = ["claude", "codex", "opencode", "agy"]

    /// The typed form as a price, or `nil` (with the reason) when the model is empty or a price is not a number ≥ 0.
    static func parse(harness: String, model: String, input: String, output: String, cache: String)
        -> Result<PriceDraft, PriceProblem>
    {
        let name = model.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return .failure(.noModel) }
        func dollars(_ text: String) -> Double? {
            let trimmed = text.trimmingCharacters(in: .whitespaces).replacingOccurrences(of: "$", with: "")
            guard let value = Double(trimmed.isEmpty ? "0" : trimmed), value.isFinite, value >= 0 else { return nil }
            return value
        }
        guard let input = dollars(input), let output = dollars(output), let cache = dollars(cache) else {
            return .failure(.notAPrice)
        }
        return .success(PriceDraft(harness: harness, model: name, input: input, output: output, cache: cache))
    }
}

enum PriceProblem: Error, Equatable {
    case noModel, notAPrice

    var message: String {
        switch self {
        case .noModel: "Name the model, as the harness reports it."
        case .notAPrice: "Prices are dollars per million tokens, 0 or more."
        }
    }
}

/// One bar of the per-day chart: a day, or an hour on Today.
struct DaySpend: Equatable, Sendable {
    var day: Date
    var totals: SpendTotals
}


extension CompanyModel {
    /// The period's tasks added up by project key, biggest first.
    func costByProject() -> [(key: String, name: String, totals: SpendTotals)] {
        Dictionary(grouping: costTasks, by: \.projectKey)
            .map { key, tasks in (key, projects.first { $0.key == key }?.name ?? key, SpendTotals(tasks)) }
            .sorted { $0.totals.tokens > $1.totals.tokens }
    }

    /// A budget row's status word and tone: ok, warn past its mark, stopped at the cap.
    func budgetWord(_ budget: BudgetInfo) -> (word: String, status: AinkradStatus) {
        if budget.fraction >= 1 { return ("stopped", .danger) }
        return budget.fraction >= budget.warnFraction ? ("warn", .warning) : ("ok", .success)
    }

    /// Where a budget's warn % comes from (decision #52): set on the budget, or the company's (or server's).
    func warnScope(_ budget: BudgetInfo) -> AinkradValueScope {
        let company = limits["budget.warn_percent"]
        let inherited = company.map {
            "\($0.source?.split(separator: ":").first.map(String.init) ?? "server") \($0.value)%"
        }
        if let company, Int64(budget.warnPercent) == company.value {
            return .inherited(from: company.source?.split(separator: ":").first.map(String.init) ?? "server")
        }
        return .overridden(
            at: budget.scope.split(separator: ":").first.map(String.init) ?? "budget", inheritedValue: inherited)
    }
}

// MARK: - Why stuck

extension StuckInfo {
    /// Stuck (red): nothing moves it without you or a change. Slowing (amber): something will, later than usual.
    var isSlowing: Bool {
        ["reviewer_inactive", "review_no_reviewer", "in_progress_idle", "todo_idle", "next_actor_inactive"]
            .contains(kind)
    }

    var glyph: String {
        switch kind {
        case "wake_no_runner", "run_queued_no_lease": "☾"
        case "agent_paused_by_breaker": "↻"
        case "blocked_no_blocker", "blocked_blockers_closed": "⛓"
        case "reviewer_inactive", "review_no_reviewer", "in_progress_idle", "todo_idle", "next_actor_inactive": "⧗"
        case "runner_disk_full": "⛁"
        default: "⚡"
        }
    }
}

extension CompanyModel {
    /// The team lead of an issue's project: who a stuck issue is reassigned or escalated to.
    func lead(ofProject project: Int64?) -> AgentInfo? {
        guard let team = projects.first(where: { $0.id == project })?.teamID else { return nil }
        let seat = departments.flatMap(\.teams).first { $0.id == team }?.seats.first { $0.teamRole == "team_lead" }
        return agent(seat?.agentID)
    }

    /// Stuck issues in a project (`nil` = all), stuck first then slowing, keeping the server's order within each.
    func stuckList(project: Int64?) -> (stuck: [StuckInfo], slowing: [StuckInfo]) {
        let shown = stuck.filter { project == nil || issue($0.issueID)?.projectID == project }
        return (shown.filter { !$0.isSlowing }, shown.filter(\.isSlowing))
    }
}
