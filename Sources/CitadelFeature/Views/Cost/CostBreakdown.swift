import AinkradAppKit
import SwiftUI

/// One row of the breakdown: what it is, its weight, its amount, and where a tap goes.
private struct BreakdownItem: Identifiable {
    let id: String
    var name: String
    var agent: AgentInfo?
    var weight: Double
    var amount: String
    var warns = false
    var open: () -> Void
}

/// `.cs-brk`: Department / Project / Agent / Account — a donut and ranked bars (dollars when anything was priced,
/// else tokens); rows open their screen. Account has no donut: this company's use of each account.
struct BreakdownCard: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        AinkradBentoTile(padding: skin.size.s14) {
            VStack(alignment: .leading, spacing: skin.size.s12) {
                Text("Breakdown").citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                AinkradGlideTabs(
                    ["department", "project", "agent", "account"].map { AinkradGlideTab($0, title: $0.capitalized) },
                    selection: Binding(get: { tab }, set: { model.costPage.breakdownTab = $0 }), height: skin.size.s32)
                Group {
                    if tab == "account" { accounts } else { donutBody(items) }
                }
                .id(tab)
                .transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: tab)
    }

    private var tab: String { model.costPage.breakdownTab }

    private var palette: [Color] {
        [
            skin.color(skin.palette.accentPrimary), skin.color(skin.palette.accentViolet),
            skin.color(skin.palette.accentSecondary), skin.color(skin.palette.accentTertiary),
            skin.color(skin.palette.success), skin.color(skin.palette.warning),
        ]
    }

    private var items: [BreakdownItem] {
        func rows(_ list: [(String, String, AgentInfo?, SpendTotals, () -> Void)]) -> [BreakdownItem] {
            let dollars = list.contains { $0.3.costMicros > 0 }
            return list.map { id, name, agent, totals, open in
                BreakdownItem(
                    id: id, name: name, agent: agent,
                    weight: Double(dollars ? totals.costMicros : totals.tokens), amount: totals.amount,
                    warns: totals.costMicros == 0 && totals.unpricedTokens > 0, open: open)
            }
            .sorted { $0.weight > $1.weight }
        }
        switch tab {
        case "project":
            return rows(
                model.costByProject().map { row in
                    let project = model.projects.first { $0.key == row.key }
                    return (
                        "\(row.key)", "\(row.key)  \(row.name)", nil, row.totals,
                        {
                            if let project { model.projectsPage.selected = project.id }
                            store.screen = .projects
                        }
                    )
                })
        case "agent":
            return rows(
                model.costByAgent.map { row in
                    let agent = model.agent(row.id)
                    return (
                        "\(row.id ?? 0)", agent?.name ?? "Agent", agent, row.totals,
                        {
                            if let id = row.id { store.open(.agent(id)) }
                        }
                    )
                })
        default:
            return rows(
                model.costByDepartment.map { row in
                    (
                        "\(row.id ?? 0)", model.departments.first { $0.id == row.id }?.name ?? "No department", nil,
                        row.totals, { store.screen = .org }
                    )
                })
        }
    }

    @ViewBuilder private func donutBody(_ items: [BreakdownItem]) -> some View {
        if items.isEmpty {
            Text("No runs in this period").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
        } else {
            let top = items.map(\.weight).max() ?? 1
            let totalMicros = items.count
            HStack(alignment: .center, spacing: skin.size.s16) {
                AinkradSegmentDonut(
                    segments: items.enumerated().map {
                        AinkradDonutSegment(
                            id: $0.offset, value: $0.element.weight, color: palette[$0.offset % palette.count])
                    }, diameter: skin.size.s124, lineWidth: skin.size.s16
                ) {
                    VStack(spacing: 0) {
                        Text(total).citadelFont("t17", weight: "bold", mono: true).foregroundStyle(
                            skin.color(skin.text.primary))
                        Text("\(totalMicros) \(tab)\(totalMicros == 1 ? "" : "s")").citadelFont("t10_5")
                            .foregroundStyle(skin.color(skin.text.faint))
                    }
                }
                VStack(alignment: .leading, spacing: skin.size.s9) {
                    ForEach(Array(items.enumerated()), id: \.element.id) { index, item in
                        row(item, color: palette[index % palette.count], top: top)
                    }
                    if tab == "agent" {
                        AinkradTapArea(action: { store.screen = .org }) {
                            Text("All \(model.agents.count) agents ›").citadelFont("t11")
                                .foregroundStyle(skin.color(skin.text.faint))
                        }
                        .padding(.top, skin.size.s4)
                    }
                }
            }
        }
    }

    /// The donut's middle: the tab's total, dollars when anything was priced.
    private var total: String {
        let totals: [SpendTotals] =
            switch tab {
            case "project": model.costByProject().map(\.totals)
            case "agent": model.costByAgent.map(\.totals)
            default: model.costByDepartment.map(\.totals)
            }
        let micros = totals.map(\.costMicros).reduce(0, +)
        return micros > 0 ? Fmt.dollars(micros: micros) : Fmt.tokens(totals.map(\.tokens).reduce(0, +))
    }

    private func row(_ item: BreakdownItem, color: Color, top: Double) -> some View {
        let amber = skin.color(skin.palette.warning)
        return HStack(spacing: skin.size.s12) {
            AinkradTapArea(action: item.open) {
                HStack(spacing: skin.size.s7) {
                    RoundedRectangle(cornerRadius: skin.size.s3).fill(color).frame(
                        width: skin.size.s9, height: skin.size.s9)
                    if let agent = item.agent { AgentFigure(agent: agent, model: model, size: skin.size.s18) }
                    Text(item.name).lineLimit(1).foregroundStyle(skin.color(skin.text.primary))
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .contentShape(Rectangle())
            }
            .ainkradHoverLift(0, cornerRadius: skin.size.s4)
            AinkradFillTrack(fraction: item.weight / max(top, 1), fill: AnyShapeStyle(item.warns ? amber : color))
                .frame(maxWidth: .infinity)
            Text(item.amount).citadelFont("t11", mono: true)
                .foregroundStyle(item.warns ? amber : skin.color(skin.text.muted))
                .frame(width: skin.size.s70, alignment: .trailing)
        }
        .citadelFont("t12")
    }

    /// This company's use of each account: kind chip, share bar, tokens.
    private var accounts: some View {
        let top = Double(model.accountUse.map(\.tokens).max() ?? 1)
        return VStack(alignment: .leading, spacing: skin.size.s9) {
            if model.accountUse.isEmpty {
                Text("No account use yet").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
            }
            ForEach(model.accountUse) { use in
                let subscription = model.accounts[use.id]?.billing == "subscription"
                let tint = subscription ? skin.color(skin.palette.accentViolet) : skin.color(skin.palette.accentPrimary)
                HStack(spacing: skin.size.s12) {
                    AinkradTapArea(action: { store.screen = .accounts }) {
                        HStack(spacing: skin.size.s7) {
                            Text(use.label).citadelFont("t12", mono: true).foregroundStyle(
                                skin.color(skin.text.primary)
                            )
                            .lineLimit(1)
                            AinkradStatePill(text: subscription ? "sub" : "API $", tint: tint)
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    AinkradFillTrack(fraction: Double(use.tokens) / max(top, 1), fill: AnyShapeStyle(tint)).frame(
                        maxWidth: .infinity)
                    Text("\(Fmt.tokens(use.tokens)) tok").citadelFont("t11", mono: true)
                        .foregroundStyle(skin.color(skin.text.muted)).frame(width: skin.size.s70, alignment: .trailing)
                }
            }
            Text(
                "Bar = \(store.company?.name ?? "this company")'s use of each account; other companies' use never shows here."
            )
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        }
    }
}

/// `.cs-tasks`: per task this period — key, title, a token bar, wall time, dollars ("sub" / "unpriced"); sorted by
/// Tokens / Time / $; a row opens its requirement (or Runs).
struct PerTaskCard: View {
    enum Sort: String, CaseIterable { case tokens, time, dollars }
    let store: CitadelStore
    let model: CompanyModel
    let period: CostPeriod
    @State private var sort: Sort = .tokens
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var sorted: [TaskCostInfo] {
        switch sort {
        case .tokens: model.costTasks.sorted { $0.tokens > $1.tokens }
        case .time: model.costTasks.sorted { $0.secs > $1.secs }
        case .dollars: model.costTasks.sorted { $0.costMicros > $1.costMicros }
        }
    }

    var body: some View {
        let top = Double(model.costTasks.map(\.tokens).max() ?? 1)
        AinkradBentoTile(padding: skin.size.s14) {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                HStack(alignment: .firstTextBaseline, spacing: skin.size.s8) {
                    Text("Per task").citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                    Text(period == .today ? "today" : "this \(period.rawValue)").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                    Spacer()
                    AinkradMiniSegment(
                        options: [(.tokens, "Tokens"), (.time, "Time"), (.dollars, "$")], selection: $sort)
                }
                if model.costTasks.isEmpty {
                    Text("No runs in this period").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                }
                ForEach(Array(sorted.prefix(10).enumerated()), id: \.element.id) { index, task in
                    TaskRow(task: task, top: top, index: index) { open(task) }
                        .ainkradRiseIn(delay: 0.03 * Double(index))
                }
                Text("Each task starts a fresh session — no giant resumed context. \"sub\" = subscription tokens.")
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: sorted.map(\.id))
    }

    private func open(_ task: TaskCostInfo) {
        if let requirement = model.issue(task.issueID)?.requirementID {
            model.requirementsPage.selectedID = requirement
            store.screen = .requirements
        } else {
            store.screen = .runs
        }
    }
}

private struct TaskRow: View {
    let task: TaskCostInfo
    let top: Double
    let index: Int
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        AinkradTapArea(action: open) {
            HStack(spacing: skin.size.s10) {
                Text(task.key).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.palette.accentSecondary))
                    .frame(width: skin.size.s56, alignment: .leading)
                Text(task.title).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: skin.size.s8) {
                    AinkradFillTrack(
                        fraction: Double(task.tokens) / max(top, 1),
                        fill: AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    skin.color(skin.palette.accentPrimary), skin.color(skin.palette.accentSecondary),
                                ],
                                startPoint: .leading, endPoint: .trailing)))
                    Text(Fmt.tokens(task.tokens)).frame(width: skin.size.s36, alignment: .trailing)
                }
                .frame(width: skin.size.s120)
                Text(Fmt.duration(TimeInterval(task.secs))).frame(width: skin.size.s62, alignment: .trailing)
                Text(task.dollarsWord).foregroundStyle(dollarsTint).frame(width: skin.size.s64, alignment: .trailing)
            }
            .citadelFont("t11", mono: true)
            .foregroundStyle(skin.color(skin.text.muted))
            .padding(.horizontal, skin.size.s10)
            .padding(.vertical, skin.size.s8)
            .background(shape.fill(skin.color(.palette("foreground", hovering ? skin.opacity.o06 : skin.opacity.o03))))
            .contentShape(shape)
        }
        .offset(x: hovering && !reduceMotion ? skin.size.s2 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }

    private var dollarsTint: Color {
        if task.pricedRuns == 0 && task.unpricedRuns > 0 { return skin.color(skin.palette.warning) }
        if task.pricedRuns == 0 && task.subscriptionRuns > 0 { return skin.color(skin.palette.accentViolet) }
        return task.costMicros > 4_000_000 ? skin.color(skin.palette.warning) : skin.color(skin.text.muted)
    }
}
