import AinkradAppKit
import SwiftUI

/// Screen 09: three kinds of spend never mixed into one number — priced dollars, unpriced runs and tokens (never
/// $0), subscription tokens — per day, by project, by account (this company's share only), per task, and the
/// budgets with their warn marks. Today / Week / Month / Sprint; Export CSV.
struct CostView: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var period: CostPeriod = .month
    @State private var pricing = false
    @State private var editing: BudgetInfo?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    private var totals: SpendTotals { SpendTotals(model.costTasks) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Cost", crumb: crumb) {
                HStack(spacing: skin.size.s8) {
                    AinkradSegmentedPicker(items: CostPeriod.allCases, selection: $period) { $0.title }
                        .disabledOptions { $0 == .sprint && model.sprint == nil }
                        .controlSize(.small).fixedSize()
                    AinkradIconButton(systemName: "square.and.arrow.down", size: skin.size.s30, tooltip: "Export CSV") {
                        store.exportCostCSV()
                    }
                    .outlineBox().disabled(model.costTasks.isEmpty)
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s14) {
                    kpis
                    PerDayChart(days: model.costDays, hourly: period == .today)
                    HStack(alignment: .top, spacing: skin.size.s14) {
                        ByDepartmentTile(model: model)
                        ByProjectTile(rows: model.costByProject())
                        ByAgentTile(store: store, model: model)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    HStack(alignment: .top, spacing: skin.size.s14) {
                        AccountShareTile(store: store, model: model)
                        PerTaskTile(tasks: model.costTasks)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                    BudgetsTile(model: model) { editing = $0 }
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.bottom, skin.size.s20)
            }
            .offlineDimmed()
        }
        .onChange(of: period, initial: true) { _, period in
            if model.costPeriod != period { store.loadCost(period) }
        }
        .ainkradPanelModal(isPresented: $pricing, contentWidth: skin.size.s440) {
            SetPriceForm(store: store, isPresented: $pricing)
        }
        .ainkradPanelModal(
            isPresented: Binding(get: { editing != nil }, set: { if !$0 { editing = nil } }),
            contentWidth: skin.size.s440
        ) {
            if let editing {
                EditBudgetForm(
                    store: store, budget: editing, inherited: inheritedWarn,
                    overridden: { if case .overridden = model.warnScope(editing) { true } else { false } }(),
                    isPresented: Binding(get: { self.editing != nil }, set: { if !$0 { self.editing = nil } }))
            }
        }
    }

    /// The company's (or server's) warn %, what an empty Warn at inherits.
    private var inheritedWarn: String { "\(model.limits["budget.warn_percent"]?.value ?? 80)%" }

    /// "October · day 22 of 31 · 3 budgets".
    private var crumb: Text {
        let now = Date()
        let calendar = Calendar.current
        let day = calendar.component(.day, from: now)
        let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
        var parts = ["\(now.formatted(.dateTime.month(.wide))) · day \(day) of \(days)"]
        if let company = model.budgets.first(where: { $0.scope.hasPrefix("company:") }) {
            parts.append("company budget \(Fmt.tokens(company.cap)) tokens / \(company.period)")
        }
        return Text(parts.joined(separator: " · ")).foregroundStyle(skin.color(skin.text.muted))
    }

    private var kpis: some View {
        let t = totals
        return VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(alignment: .top, spacing: skin.size.s14) {
                CostKPI(
                    label: "Priced", value: Fmt.dollars(micros: t.costMicros), unit: nil, tone: nil,
                    detail: Text("API-billed runs at known prices · \(Fmt.tokens(t.pricedTokens)) tokens"))
                CostKPI(
                    label: "Unpriced", value: "\(t.unpricedRuns)",
                    unit: "run\(t.unpricedRuns == 1 ? "" : "s") · \(Fmt.tokens(t.unpricedTokens)) tokens",
                    tone: t.unpricedRuns > 0 ? .warning : nil,
                    detail: Text("A model with no price set — counted in tokens, never as $0"),
                    // Decision #37: "Set a price…" inline (POST /prices).
                    action: ("Set a price…", { pricing = true }))
                CostKPI(
                    label: "Subscription", value: Fmt.tokens(t.subscriptionTokens), unit: "tokens", tone: nil,
                    detail: Text("\(t.subscriptionRuns) runs on Claude Max / Codex Pro logins — tokens, not dollars"))
            }
            .fixedSize(horizontal: false, vertical: true)
            if t.pricedTokens + t.unpricedTokens + t.subscriptionTokens > 0 { SpendSplitBar(spend: t.spend) }
        }
    }
}

/// A KPI tile: label, big value + unit, a line under it, and an optional disabled inline action.
private struct CostKPI: View {
    let label: String
    let value: String
    let unit: String?
    let tone: AinkradChartTone?
    let detail: Text
    var action: (title: String, perform: () -> Void)?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(skin.labelCased(label)).citadelFont("t10", weight: "semibold")
                    .foregroundStyle(tone?.tint(skin) ?? skin.color(skin.text.muted))
                HStack(alignment: .firstTextBaseline, spacing: skin.size.s4) {
                    Text(value).citadelFont("t26", weight: "semibold")
                        .foregroundStyle(tone?.tint(skin) ?? skin.color(skin.text.primary))
                    if let unit { Text(unit).citadelFont("t13").foregroundStyle(skin.color(skin.text.muted)) }
                }
                detail.citadelFont("t11_5").foregroundStyle(skin.color(skin.text.muted))
                    .fixedSize(horizontal: false, vertical: true)
                if let action {
                    AinkradButton(title: action.title, style: .ghost, action: action.perform)
                        .borderless().secondaryAccent().compact().fixedSize()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .rim(tone)
    }
}
