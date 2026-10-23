import AinkradAppKit
import SwiftUI

/// The agent page's rail: month budget with warn / hard marks, caps, setup, and a week of runs.
struct AgentRail: View {
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s12) {
                if let budget = model.budgets.first(where: { $0.scope == "agent:\(agent.id)" && $0.period == "month" })
                {
                    RailLabel(title: "Budget · \(budget.periodKey)")
                    HStack(alignment: .firstTextBaseline, spacing: skin.size.s4) {
                        Text(Fmt.tokens(budget.spent)).citadelFont("t24", weight: "semibold")
                            .foregroundStyle(skin.color(skin.text.primary))
                        Text("/ \(Fmt.tokens(budget.cap)) tok").citadelFont("t13").foregroundStyle(
                            skin.color(skin.text.muted))
                    }
                    AinkradBudgetBar(
                        label: "Month budget", value: Double(budget.spent), limit: Double(budget.cap),
                        warnFraction: budget.warnFraction, isThick: true)
                    Text(
                        "warn \(Fmt.tokens(budget.cap * Int64(budget.warnPercent) / 100)) · hard stop \(Fmt.tokens(budget.cap))"
                    )
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                }
                VStack(spacing: skin.size.s4) {
                    if let cap = model.limit("run.token_cap") {
                        AinkradStatRow(label: "Per-run cap", value: "\(Fmt.tokens(cap.value)) tokens")
                            .sentenceCaseLabel()
                    }
                    if let loop = model.limit("breaker.loop_threshold") {
                        AinkradStatRow(label: "Loop breaker", value: "\(loop.value) same failures").sentenceCaseLabel()
                    }
                }
                RailLabel(title: "Setup").padding(.top, skin.size.s6)
                VStack(spacing: skin.size.s4) {
                    let version = model.agentRuns[agent.id]?.first?.harnessVersion
                    AinkradStatRow(label: "Harness", value: "\(agent.harnessName)\(version.map { " \($0)" } ?? "")")
                        .sentenceCaseLabel()
                    AinkradStatRow(label: "Model", value: agent.model).sentenceCaseLabel()
                    AinkradStatRow(label: "Runner tags", value: agent.runnerTags.joined(separator: " "))
                        .sentenceCaseLabel()
                    if let boss = model.agent(agent.reportsTo) {
                        AinkradStatRow(label: "Reports to", value: boss.name).sentenceCaseLabel()
                    }
                    AinkradStatRow(label: "Status", value: agent.status.replacingOccurrences(of: "_", with: " "))
                        .sentenceCaseLabel()
                }
                RailLabel(title: "This week").padding(.top, skin.size.s6)
                let week = WeekOfRuns(runs: model.agentRuns[agent.id] ?? [])
                AinkradBarChart(title: "Runs this week", bars: week.bars, emptyMessage: "No runs this week")
                    .frame(height: skin.size.s140)
                Text(week.caption).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            .padding(.horizontal, skin.size.s16)
            .padding(.vertical, skin.size.s14)
        }
        .frame(width: skin.size.s300)
        .frame(maxHeight: .infinity)
        .background(theme.surface.opacity(skin.opacity.o35))
    }
}

struct RailLabel: View {
    let title: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(skin.labelCased(title)).citadelFont("t10", weight: "semibold").tracking(skin.size.s1 / 2)
            .foregroundStyle(skin.color(skin.text.muted))
    }
}

/// The last seven days of an agent's runs: one bar a day, stacked by how they ended.
struct WeekOfRuns {
    let bars: [AinkradChartBar]
    let caption: String

    init(runs: [RunInfo], now: Date = Date(), calendar: Calendar = .current) {
        let today = calendar.startOfDay(for: now)
        let days = (0..<7).reversed().compactMap { calendar.date(byAdding: .day, value: -$0, to: today) }
        let recent = runs.filter { $0.queuedAt >= days[0] && !$0.isLive }
        bars = days.map { day in
            let mine = recent.filter { calendar.isDate($0.queuedAt, inSameDayAs: day) }
            return AinkradChartBar(
                label: day.formatted(.dateTime.weekday(.narrow)),
                segments: [
                    AinkradBarSegment(
                        name: "succeeded", value: Double(mine.filter { $0.endWord == "succeeded" }.count),
                        tone: .accentSecondary),
                    AinkradBarSegment(
                        name: "cap hit", value: Double(mine.filter { $0.endWord == "cap hit" }.count), tone: .warning),
                    AinkradBarSegment(
                        name: "failed",
                        value: Double(
                            mine.filter { ["failed", "runner lost", "timed out"].contains($0.endWord) }.count),
                        tone: .danger),
                ])
        }
        let succeeded = recent.filter { $0.endWord == "succeeded" }.count
        let failed = recent.filter { ["failed", "runner lost", "timed out"].contains($0.endWord) }.count
        let capped = recent.filter { $0.endWord == "cap hit" }.count
        caption = "\(recent.count) runs · \(succeeded) succeeded · \(failed) failed · \(capped) cap hit"
    }
}
