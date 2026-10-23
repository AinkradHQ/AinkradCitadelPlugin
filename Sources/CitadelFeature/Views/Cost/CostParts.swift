import AinkradAppKit
import SwiftUI

/// Per day: priced, unpriced and subscription tokens stacked in the mockup's colours.
struct PerDayChart: View {
    let days: [DaySpend]
    /// Today: one bar per hour.
    var hourly = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                TileHead(title: hourly ? "Per hour · tokens" : "Per day · tokens")
                AinkradBarChart(
                    title: "Per day", bars: days.map(bar), emptyMessage: "No runs in this period",
                    format: { Fmt.tokens(Int64($0)) }
                )
                .frame(height: skin.size.s140)
            }
        }
    }

    private func bar(_ day: DaySpend) -> AinkradChartBar {
        let t = day.totals
        return AinkradChartBar(
            label: hourly
                ? day.day.formatted(.dateTime.hour()) : day.day.formatted(.dateTime.month(.abbreviated).day()),
            segments: [
                AinkradBarSegment(name: "Priced", value: Double(t.pricedTokens), tone: .accentSecondary),
                AinkradBarSegment(name: "Unpriced", value: Double(t.unpricedTokens), tone: .warning),
                AinkradBarSegment(name: "Subscription", value: Double(t.subscriptionTokens), tone: .accentViolet),
            ])
    }
}

/// One "name · bar · amount" row of the breakdown tiles.
struct BreakdownRow: View {
    let name: Text
    let value: Double
    let max: Double
    let amount: String
    var tone: AinkradChartTone = .accentSecondary
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s10) {
            name.citadelFont("t12_5").lineLimit(1).frame(width: skin.size.s120, alignment: .leading)
            AinkradBudgetBar(
                label: amount, value: value, limit: Swift.max(max, 1), warnFraction: nil, showsHardLimit: false,
                tone: tone)
            Text(amount).citadelFont("t12", mono: true).foregroundStyle(skin.color(skin.text.muted))
                .frame(width: skin.size.s80, alignment: .trailing)
        }
    }
}

struct ByProjectTile: View {
    let rows: [(key: String, name: String, totals: SpendTotals)]
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let top =
            rows.map { Double($0.totals.tokens) }
            .max() ?? 1
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                TileHead(title: "By project")
                if rows.isEmpty { empty("No runs in this period") }
                ForEach(rows, id: \.key) { row in
                    let t = row.totals
                    BreakdownRow(
                        name: Text("\(row.key) ").foregroundStyle(theme.accentSecondary)
                            + Text(row.name).foregroundStyle(skin.color(skin.text.primary)),
                        value: Double(t.pricedTokens + t.unpricedTokens + t.subscriptionTokens), max: top,
                        amount: t.costMicros > 0
                            ? Fmt.dollars(micros: t.costMicros)
                            : "\(Fmt.tokens(t.unpricedTokens + t.subscriptionTokens)) tok")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func empty(_ text: String) -> some View {
        Text(text).citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
    }
}

/// By account: this company's use of each pool account, subscription in violet, API in cyan.
struct AccountShareTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let top = Double(model.accountUse.map(\.tokens).max() ?? 1)
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                TileHead(title: "By account · \(store.company?.name ?? "this company")'s share", action: "Accounts →") {
                    store.screen = .accounts
                }
                if model.accountUse.isEmpty {
                    Text("No account use yet").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                }
                ForEach(model.accountUse) { use in
                    let subscription = model.accounts[use.id]?.billing == "subscription"
                    HStack(spacing: skin.size.s8) {
                        BreakdownRow(
                            name: Text(use.label).foregroundStyle(skin.color(skin.text.primary)),
                            value: Double(use.tokens), max: top, amount: "\(Fmt.tokens(use.tokens)) tok",
                            tone: subscription ? .accentViolet : .accentSecondary)
                        AinkradBadge(
                            text: subscription ? "sub" : "API",
                            tint: (subscription ? AinkradChartTone.accentViolet : .accentSecondary).tint(skin))
                    }
                }
                Text("This company's use only; other companies' use of a shared account never shows here.")
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Per task: tokens, wall time and dollars (or "sub" / "unpriced") per issue, sortable.
struct PerTaskTile: View {
    enum Sort: String, CaseIterable { case tokens, time, dollars }
    let tasks: [TaskCostInfo]
    @State private var sort: Sort = .tokens
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    private var sorted: [TaskCostInfo] {
        switch sort {
        case .tokens: tasks.sorted { $0.tokens > $1.tokens }
        case .time: tasks.sorted { $0.secs > $1.secs }
        case .dollars: tasks.sorted { $0.costMicros > $1.costMicros }
        }
    }

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                HStack {
                    TileHead(title: "Per task")
                    AinkradMenuButton(
                        items: Sort.allCases.map { option in
                            AinkradMenuItem(title: option.rawValue.capitalized, systemName: nil) { sort = option }
                        }
                    ) { Text("Sort: \(sort.rawValue) ▾") }
                }
                if tasks.isEmpty {
                    Text("No runs in this period").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                }
                ForEach(sorted.prefix(8)) { task in
                    HStack(spacing: skin.size.s10) {
                        Text(task.key).citadelFont("t11", mono: true).foregroundStyle(theme.accentSecondary)
                            .frame(width: skin.size.s60, alignment: .leading)
                        Text(task.title).citadelFont("t12_5").foregroundStyle(skin.color(skin.text.primary))
                            .lineLimit(1)
                        Spacer(minLength: skin.size.s8)
                        Group {
                            Text(Fmt.tokens(task.tokens)).frame(width: skin.size.s50, alignment: .trailing)
                            Text(Fmt.duration(TimeInterval(task.secs))).frame(
                                width: skin.size.s60, alignment: .trailing)
                            Text(task.dollarsWord)
                                .foregroundStyle(task.unpricedRuns > 0 ? status.warning : skin.color(skin.text.muted))
                                .frame(width: skin.size.s60, alignment: .trailing)
                        }
                        .citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.muted))
                    }
                }
                Text("Each task starts a fresh session. \"sub\" = subscription tokens.").citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.faint))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// Budgets at every scope: spent against the warn mark and the hard line, where the warn % comes from, and the
/// state. At the hard line new runs wait for an approved raise (screen 06).
struct BudgetsTile: View {
    let model: CompanyModel
    /// A row's Edit (shown on hover): its cap and warn %.
    var edit: (BudgetInfo) -> Void = { _ in }
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                HStack(spacing: skin.size.s10) {
                    TileHead(title: "Budgets")
                    Text(
                        "hard stop at the cap blocks new runs until you approve · warn % per budget, inherited unless set"
                    )
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                if model.budgets.isEmpty {
                    Text("No budgets set").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                }
                ForEach(model.budgets) { budget in
                    BudgetRow(model: model, budget: budget) { edit(budget) }
                }
            }
        }
    }
}

/// One budget: scope · period, the bar with its warn mark, spent / cap, warn % and where it comes from, the state;
/// hover shows Edit.
private struct BudgetRow: View {
    let model: CompanyModel
    let budget: BudgetInfo
    let edit: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
                    let state = model.budgetWord(budget)
                    HStack(spacing: skin.size.s12) {
                        Text("\(budget.label) · \(budget.period)").citadelFont("t12_5")
                            .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                            .frame(width: skin.size.s200, alignment: .leading)
                        AinkradBudgetBar(
                            label: budget.label, value: Double(budget.spent), limit: Double(budget.cap),
                            warnFraction: budget.warnFraction)
                        Text("\(Fmt.tokens(budget.spent)) / \(Fmt.tokens(budget.cap))").citadelFont("t12", mono: true)
                            .foregroundStyle(skin.color(skin.text.muted)).frame(
                                width: skin.size.s110, alignment: .trailing)
                        Text("\(budget.warnPercent)%").citadelFont("t12", mono: true)
                            .foregroundStyle(skin.color(skin.text.primary))
                        scope(model.warnScope(budget)).frame(width: skin.size.s110, alignment: .leading)
                        AinkradBadge(text: state.word, status: state.status).frame(
                            width: skin.size.s70, alignment: .leading)
                        AinkradButton(title: "Edit", style: .ghost, action: edit)
                            .borderless().secondaryAccent().compact().fixedSize()
                            .opacity(hovering ? 1 : 0)
                    }
                    .contentShape(Rectangle())
                    .onHover { hovering = $0 }
    }

    @ViewBuilder private func scope(_ scope: AinkradValueScope) -> some View {
        switch scope {
        case .inherited(let from): AinkradBadge(text: "↳ \(from)")
        case .overridden(let at, _): AinkradBadge(text: "● \(at)", tint: theme.accentSecondary)
        @unknown default: EmptyView()
        }
    }
}
