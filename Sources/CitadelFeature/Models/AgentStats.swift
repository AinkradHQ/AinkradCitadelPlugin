import Foundation

/// What the peek panel and the agent page say about an agent's work, derived from the runs the client has loaded
/// (`listAgentRuns`, up to 50). The server has no agent stats endpoint yet, so every figure covers that page.
struct AgentStats: Equatable {
    /// Runs started each day of this week, Monday first.
    let week: [Int]
    let finished: Int
    let succeeded: Int
    /// Mean cost of the priced finished runs.
    let averageMicros: Int64?
    /// Success % of each of the last eight weeks, oldest first; `nil` where it had no finished runs.
    let weekly: [Int?]
    /// Runs started this week by day (Mon…Sun) × four-hour slot (00…20).
    let heat: [[Int]]
    let todayRuns: Int
    let todayMicros: Int64

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
