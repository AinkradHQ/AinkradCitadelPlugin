import AinkradAppKit
import SwiftUI

/// Which inset drawer the Cost screen shows.
enum CostDrawer: Equatable {
    case price, newBudget
}

/// Screen 09 (prototype `cost.js`): three kinds of spend never mixed into one number — priced dollars, unpriced runs
/// and tokens (never $0), subscription tokens. The hero rings the company budget (tokens until the server stores
/// dollar caps) with its pace; the kinds, the per-day chart, the tabbed breakdown, per task, and the budgets as ring
/// cards edited inline. Set a price and New budget open as inset drawers.
struct CostView: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var period: CostPeriod = .month
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Cost", crumb: crumb) {
                AinkradDockButton(
                    "Export CSV", systemImage: "square.and.arrow.down", isEnabled: !model.costTasks.isEmpty
                ) {
                    store.exportCostCSV()
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s12) {
                    CostHero(model: model, period: $period, label: periodLabel)
                    CostKinds(model: model) { model.costPage.drawer = .price }
                    CostChartTile(model: model, hourly: period == .today)
                    HStack(alignment: .top, spacing: skin.size.s12) {
                        BreakdownCard(store: store, model: model)
                        PerTaskCard(store: store, model: model, period: period)
                    }
                    BudgetsCard(store: store, model: model) { model.costPage.drawer = .newBudget }
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.bottom, skin.size.s20)
            }
            .scrollIndicators(.never)
            .offlineDimmed()
        }
        .opsDrawer(
            isPresented: Binding(get: { model.costPage.drawer != nil }, set: { if !$0 { model.costPage.drawer = nil } })
        ) {
            let shown = Binding(get: { model.costPage.drawer != nil }, set: { if !$0 { model.costPage.drawer = nil } })
            switch model.costPage.drawer {
            case .price: SetPriceForm(store: store, isPresented: shown)
            case .newBudget: NewBudgetForm(store: store, model: model, isPresented: shown)
            case nil: EmptyView()
            }
        }
        .onChange(of: period, initial: true) { _, period in
            if model.costPeriod != period { store.loadCost(period) }
        }
        .onAppear { if let loaded = model.costPeriod { period = loaded } }
    }

    /// "October · day 22 of 31", "This week · Oct 20 → 26", "Today · Oct 24", "Sprint CIT S4 · day 6 of 10".
    private var periodLabel: String {
        let now = Date()
        let calendar = Calendar.current
        switch period {
        case .today: return "Today · \(now.formatted(.dateTime.month(.abbreviated).day()))"
        case .week:
            guard let week = calendar.dateInterval(of: .weekOfYear, for: now) else { return "This week" }
            let end = week.end.addingTimeInterval(-1)
            return
                "This week · \(week.start.formatted(.dateTime.month(.abbreviated).day())) → \(end.formatted(.dateTime.day()))"
        case .month:
            let day = calendar.component(.day, from: now)
            let days = calendar.range(of: .day, in: .month, for: now)?.count ?? 30
            return "\(now.formatted(.dateTime.month(.wide))) · day \(day) of \(days)"
        case .sprint:
            guard let sprint = model.sprint else { return "Sprint" }
            guard let start = sprint.startsOn, let end = sprint.endsOn else { return "Sprint \(sprint.name)" }
            let day = (calendar.dateComponents([.day], from: start, to: now).day ?? 0) + 1
            let days = (calendar.dateComponents([.day], from: start, to: end).day ?? 0) + 1
            return "Sprint \(sprint.name) · day \(day) of \(days)"
        }
    }

    /// "October · day 22 of 31 · company budget 5M tok".
    private var crumb: Text {
        var parts = [periodLabel]
        if let company = model.budgets.first(where: { $0.scope.hasPrefix("company:") }) {
            parts.append("company budget \(Fmt.tokens(company.cap)) tok")
        }
        return Text(parts.joined(separator: "  ·  ")).foregroundStyle(skin.color(skin.text.muted))
    }
}
