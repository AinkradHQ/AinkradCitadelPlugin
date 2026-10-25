import CitadelClient
import Foundation

/// What the peek panel and the agent page say about an agent's work. From API minor 18 it is the server's
/// `GET /agents/{id}/stats` (runs by day, success by week, a 28-day heatmap, the mean cost); until that has
/// answered, and on an older server, it is derived from the runs the client has loaded (`listAgentRuns`, up to 50),
/// so every figure then covers that page.
struct AgentStats: Equatable {
    /// Runs started each day of this week, Monday first.
    private(set) var week: [Int]
    private(set) var finished: Int
    private(set) var succeeded: Int
    /// Mean cost of the priced finished runs.
    private(set) var averageMicros: Int64?
    /// Success % of each of the last eight weeks, oldest first; `nil` where it had no finished runs.
    private(set) var weekly: [Int?]
    /// Runs started by day (Mon…Sun) × four-hour slot (00…20): this week from the loaded runs, the last 28 days
    /// (UTC slots) from the server.
    private(set) var heat: [[Int]]
    private(set) var todayRuns: Int
    private(set) var todayMicros: Int64
    /// The figures are the server's.
    private(set) var isServer = false

    /// Runs of the last 28 days, when the server counted them.
    var heatSpan: String { isServer ? "last 4 weeks" : "this week" }
    var weekTotal: Int { week.reduce(0, +) }
    var successPercent: Int? { finished > 0 ? Int((Double(succeeded) / Double(finished) * 100).rounded()) : nil }
    var retried: Int { finished - succeeded }

    init(runs: [RunInfo], now: Date = Date(), calendar base: Calendar = .current) {
        var calendar = base
        calendar.firstWeekday = 2
        let monday = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? calendar.startOfDay(for: now)
        let thisWeek = runs.filter { $0.queuedAt >= monday }
        func dayIndex(_ date: Date) -> Int {
            min(6, max(0, calendar.dateComponents([.day], from: monday, to: date).day ?? 0))
        }
        var week = Array(repeating: 0, count: 7)
        var heat = Array(repeating: Array(repeating: 0, count: 6), count: 7)
        for run in thisWeek {
            let started = run.startedAt ?? run.queuedAt
            week[dayIndex(run.queuedAt)] += 1
            heat[dayIndex(started)][min(5, calendar.component(.hour, from: started) / 4)] += 1
        }
        self.week = week
        self.heat = heat
        let ended = runs.filter { !$0.isLive }
        finished = ended.count
        succeeded = ended.filter { $0.state == "succeeded" }.count
        let priced = ended.compactMap(\.costMicros)
        averageMicros = priced.isEmpty ? nil : priced.reduce(0, +) / Int64(priced.count)
        weekly = (0..<8).reversed().map { back -> Int? in
            guard let start = calendar.date(byAdding: .weekOfYear, value: -back, to: monday),
                let end = calendar.date(byAdding: .weekOfYear, value: 1, to: start)
            else { return nil }
            let mine = ended.filter { $0.queuedAt >= start && $0.queuedAt < end }
            guard !mine.isEmpty else { return nil }
            return Int((Double(mine.filter { $0.state == "succeeded" }.count) / Double(mine.count) * 100).rounded())
        }
        let today = runs.filter { calendar.isDate($0.queuedAt, inSameDayAs: now) }
        todayRuns = today.count
        todayMicros = today.compactMap(\.costMicros).reduce(0, +)
    }

    /// The server's stats over the loaded runs: its figures win wherever it sent them.
    init(runs: [RunInfo], server: Schemas.AgentStats?, now: Date = Date(), calendar base: Calendar = .current) {
        self.init(runs: runs, now: now, calendar: base)
        guard let server else { return }
        isServer = true
        var utc = Calendar(identifier: .gregorian)
        utc.timeZone = TimeZone(identifier: "UTC") ?? .gmt
        utc.firstWeekday = 2
        let monday = utc.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        let day = DateFormatter()
        day.calendar = utc
        day.timeZone = utc.timeZone
        day.dateFormat = "yyyy-MM-dd"
        var week = Array(repeating: 0, count: 7)
        for point in server.runsByDay {
            guard let date = day.date(from: point.day), date >= monday else { continue }
            week[min(6, max(0, utc.dateComponents([.day], from: monday, to: date).day ?? 0))] += Int(point.runs)
        }
        self.week = week
        finished = server.successByWeek.reduce(0) { $0 + Int($1.runs) }
        succeeded = server.successByWeek.reduce(0) { $0 + Int($1.succeeded) }
        weekly = server.successByWeek.map {
            $0.runs > 0 ? Int((Double($0.succeeded) / Double($0.runs) * 100).rounded()) : nil
        }
        averageMicros = server.avgCostMicros
        if server.heatmap.count == 7, server.heatmap.allSatisfy({ $0.count == 6 }) {
            heat = server.heatmap.map { $0.map(Int.init) }
        }
        let today = day.string(from: now)
        todayRuns = server.runsByDay.last { $0.day == today }.map { Int($0.runs) } ?? 0
        todayMicros = server.dailySpend.last { $0.day == today }?.costUsdMicros ?? 0
    }

    /// The month's running spend by day from the server's `daily_spend`: priced dollars (millionths) or tokens.
    static func burn(server: Schemas.AgentStats, dollars: Bool) -> [Int64] {
        var total: Int64 = 0
        return server.dailySpend.map {
            total += dollars ? $0.costUsdMicros : $0.tokens
            return total
        }
    }

    /// Cumulative tokens by day this month for the burn chart. Spend before the loaded runs (the budget's `spent`
    /// less what they add up to) is the line's starting value, so the tip lands on the budget's real spend.
    static func burn(runs: [RunInfo], spent: Int64, now: Date = Date(), calendar: Calendar = .current) -> [Int64] {
        guard let month = calendar.dateInterval(of: .month, for: now) else { return [] }
        let today = (calendar.dateComponents([.day], from: month.start, to: now).day ?? 0) + 1
        var daily = Array(repeating: Int64(0), count: today)
        for run in runs where run.queuedAt >= month.start && run.queuedAt <= now {
            let day = calendar.dateComponents([.day], from: month.start, to: run.queuedAt).day ?? 0
            daily[min(today - 1, max(0, day))] += run.tokens
        }
        var total = max(0, spent - daily.reduce(0, +))
        return daily.map {
            total += $0
            return total
        }
    }
}

extension CompanyModel {
    /// An agent's stats: the server's once read, else derived from its loaded runs.
    func stats(of agent: Int64, now: Date = Date()) -> AgentStats {
        AgentStats(runs: agentRuns[agent] ?? [], server: agentStats[agent], now: now)
    }
}
