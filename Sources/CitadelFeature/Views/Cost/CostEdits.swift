import AinkradAppKit
import SwiftUI

/// By department: the period's spend cut by department (`getSpendBreakdown`), biggest first.
struct ByDepartmentTile: View {
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let rows = model.costByDepartment.sorted { $0.totals.tokens > $1.totals.tokens }
        let top = Double(rows.map(\.totals.tokens).max() ?? 1)
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                TileHead(title: "By department")
                if rows.isEmpty { faint("No runs in this period") }
                ForEach(rows, id: \.id) { row in
                    BreakdownRow(
                        name: Text(model.departments.first { $0.id == row.id }?.name ?? "No department")
                            .foregroundStyle(skin.color(skin.text.primary)),
                        value: Double(row.totals.tokens), max: top, amount: row.totals.amount)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func faint(_ text: String) -> some View {
        Text(text).citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
    }
}

/// By agent · top 5: each agent as its figure, its spend, "All 18 →" to the org.
struct ByAgentTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let rows = model.costByAgent.sorted { $0.totals.tokens > $1.totals.tokens }
        let top = Double(rows.map(\.totals.tokens).max() ?? 1)
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                TileHead(title: "By agent · top 5", action: "All \(model.agents.count) →") { store.screen = .org }
                if rows.isEmpty {
                    Text("No runs in this period").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                }
                ForEach(rows.prefix(5), id: \.id) { row in
                    let agent = model.agent(row.id)
                    HStack(spacing: skin.size.s8) {
                        if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s18) }
                        BreakdownRow(
                            name: Text(agent?.name ?? "Agent").foregroundStyle(skin.color(skin.text.primary)),
                            value: Double(row.totals.tokens), max: top, amount: row.totals.amount,
                            tone: row.totals.costMicros == 0 && row.totals.unpricedTokens > 0 ? .warning : .accentSecondary)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension SpendTotals {
    /// A breakdown row's amount: dollars when any run was priced, "unpriced" when only unpriced, else tokens.
    var amount: String {
        if costMicros > 0 { return Fmt.dollars(micros: costMicros) }
        if unpricedTokens > 0 && subscriptionTokens == 0 { return "unpriced" }
        return "\(Fmt.tokens(tokens)) tok"
    }
}

/// "Set a price…": harness, model and its dollars per million tokens; from now on, runs before stay unpriced.
struct SetPriceForm: View {
    let store: CitadelStore
    @Binding var isPresented: Bool
    @State private var harness = "opencode"
    @State private var modelName = ""
    @State private var input = ""
    @State private var output = ""
    @State private var cache = ""
    @State private var problem: PriceProblem?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Set a price").citadelFont("t15", weight: "semibold")
            Text("Runs from now on are priced; runs before stay unpriced. Dollars per million tokens.")
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            AinkradFormRow(title: "Harness") {
                AinkradSegmentedPicker(items: PriceDraft.harnesses, selection: $harness) {
                    AgentLook.harnessName($0)
                }
                .fixedSize()
            }
            AinkradFormRow(title: "Model") { AinkradTextField(text: $modelName, placeholder: "qwen3-coder") }
            AinkradFormRow(title: "Input") { AinkradTextField(text: $input, placeholder: "0.30").monospaced() }
            AinkradFormRow(title: "Output") { AinkradTextField(text: $output, placeholder: "1.20").monospaced() }
            AinkradFormRow(title: "Cache read") { AinkradTextField(text: $cache, placeholder: "0").monospaced() }
            if let problem { AinkradBanner(message: problem.message, status: .danger) }
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { isPresented = false }.fixedSize()
                AinkradButton(title: "Set price") { save() }.fixedSize()
                    .disabled(modelName.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    private func save() {
        switch PriceDraft.parse(harness: harness, model: modelName, input: input, output: output, cache: cache) {
        case .success(let price):
            store.setPrice(price)
            isPresented = false
        case .failure(let why): problem = why
        }
    }
}

/// A budget's Edit: its cap in tokens and its warn % (empty inherits), refused out of bounds — never clamped.
struct EditBudgetForm: View {
    let store: CitadelStore
    let budget: BudgetInfo
    let inherited: String
    @Binding var isPresented: Bool
    @State private var cap: String
    @State private var warn: String
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    init(store: CitadelStore, budget: BudgetInfo, inherited: String, overridden: Bool, isPresented: Binding<Bool>) {
        self.store = store
        self.budget = budget
        self.inherited = inherited
        self._isPresented = isPresented
        self._cap = State(initialValue: Fmt.tokens(budget.cap))
        self._warn = State(initialValue: overridden ? "\(budget.warnPercent)" : "")
    }

    var body: some View {
        let edit = BudgetEdit.parse(cap: cap, warn: warn)
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("\(budget.label) · \(budget.period)").citadelFont("t15", weight: "semibold")
            AinkradFormRow(title: "Cap", help: "Tokens; approved raises included.") {
                AinkradTextField(text: $cap, placeholder: "2M").monospaced()
            }
            AinkradFormRow(title: "Warn at", help: "50–99%; empty inherits \(inherited).") {
                AinkradTextField(text: $warn, placeholder: inherited).monospaced()
            }
            if case .failure(let why) = edit {
                Text(why.message).citadelFont("t11_5").foregroundStyle(status.danger)
            }
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { isPresented = false }.fixedSize()
                AinkradButton(title: "Save") {
                    guard case .success(let edit) = edit else { return }
                    store.setBudget(budget, cap: edit.cap, warnPercent: edit.warnPercent)
                    isPresented = false
                }
                .fixedSize()
                .disabled((try? edit.get()) == nil)
            }
        }
    }
}

/// A budget edit as typed: the cap in tokens (`2M`, `900k`, `1500`) and the warn % (`nil` inherits).
struct BudgetEdit: Equatable {
    var cap: Int64
    var warnPercent: Int?

    enum Problem: Error, Equatable {
        case cap, warn

        var message: String {
            switch self {
            case .cap: "The cap is a token count, 0 or more (2M, 900k)."
            case .warn: "Warn at is 50–99%, or empty to inherit."
            }
        }
    }

    static func parse(cap: String, warn: String) -> Result<BudgetEdit, Problem> {
        guard let tokens = ScopedSetting.parse(cap, unit: "tokens"), tokens >= 0 else { return .failure(.cap) }
        let typed = warn.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty { return .success(BudgetEdit(cap: tokens, warnPercent: nil)) }
        guard let percent = ScopedSetting.parse(typed, unit: "percent"), (50...99).contains(percent) else {
            return .failure(.warn)
        }
        return .success(BudgetEdit(cap: tokens, warnPercent: Int(percent)))
    }
}
