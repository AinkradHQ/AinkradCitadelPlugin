import AinkradAppKit
import SwiftUI

extension SpendTotals {
    /// A breakdown row's amount: dollars when any run was priced, "unpriced" when only unpriced, else tokens.
    var amount: String {
        if costMicros > 0 { return Fmt.dollars(micros: costMicros) }
        if unpricedTokens > 0 && subscriptionTokens == 0 { return "unpriced" }
        return "\(Fmt.tokens(tokens)) tok"
    }
}

/// Cost › Set a price (`costPrice`): the model and its dollars per million tokens. Runs are priced from now on —
/// "Past runs too" needs the server's re-cost job, and the unpriced model's name isn't reported yet.
struct SetPriceForm: View {
    let store: CitadelStore
    @Binding var isPresented: Bool
    @State private var harness = "opencode"
    @State private var modelName = ""
    @State private var input = ""
    @State private var output = ""
    @State private var cache = ""
    @State private var problem: PriceProblem?
    @State private var history: [PriceVersionInfo] = []
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let amber = skin.color(skin.palette.warning)
        AinkradDrawerPanel(
            style: .form, onClose: { isPresented = false },
            header: { AinkradDrawerCrumb(["Cost", "Set a price"], monospaced: true) }
        ) {
            AinkradDrawerHero(
                tint: amber, title: modelName.isEmpty ? "Unpriced model" : modelName,
                subtitle:
                    "via \(AgentLook.harnessName(harness)) · until a price exists its runs count as tokens only — never as $0"
            ) {
                Image(systemName: "exclamationmark.triangle").citadelFont("t20").foregroundStyle(amber)
                    .frame(width: skin.size.s52, height: skin.size.s52)
                    .background(
                        amber.opacity(skin.opacity.o18),
                        in: RoundedRectangle(cornerRadius: skin.size.s15, style: .continuous))
            } trailing: {
                EmptyView()
            }
            AinkradDrawerSection(title: "Model", hint: "as the harness reports it") {
                AinkradSegmentedPicker(items: PriceDraft.harnesses, selection: $harness) { AgentLook.harnessName($0) }
                    .fixedSize()
                AinkradTextField(text: $modelName, placeholder: "qwen3-coder").monospaced()
            }
            AinkradDrawerSection(title: "Price per 1M tokens · USD") {
                HStack(spacing: skin.size.s8) {
                    AinkradTextField(text: $input, placeholder: "0.40").monospaced()
                    AinkradTextField(text: $output, placeholder: "1.20").monospaced()
                    AinkradTextField(text: $cache, placeholder: "0").monospaced()
                }
                AinkradDrawerHint("input · output · cache read")
            }
            AinkradDrawerSection(title: "Apply to") {
                AinkradOptionGrid(
                    options: [
                        AinkradOption(
                            id: "past", title: "Past runs too", detail: "re-cost this period's unpriced runs",
                            isEnabled: false, help: "Re-pricing past runs needs the server (apply_from)"),
                        AinkradOption(id: "now", title: "From now on", detail: "runs before stay unpriced"),
                    ], columns: 2, isOn: { $0 == "now" }, pick: { _ in })
            }
            if !history.isEmpty {
                AinkradDrawerSection(title: "Earlier prices") {
                    ForEach(history.reversed(), id: \.version) {
                        Text($0.line).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    }
                }
            }
            AinkradDrawerHint("Audited · company setting. Runs from now on move from unpriced to priced.")
            if let problem { AinkradBanner(message: problem.message, status: .danger) }
        } footer: {
            Spacer()
            AinkradDockButton("Cancel") { isPresented = false }
            AinkradDockButton(
                "Save price", tone: .primary, isEnabled: !modelName.trimmingCharacters(in: .whitespaces).isEmpty
            ) { save() }
        }
        .task(id: priced) {
            let name = modelName.trimmingCharacters(in: .whitespaces)
            try? await Task.sleep(for: .milliseconds(300))
            guard !Task.isCancelled else { return }
            history = name.isEmpty ? [] : await store.priceHistory(harness: harness, model: name)
        }
    }

    private var priced: String { "\(harness)|\(modelName.trimmingCharacters(in: .whitespaces))" }

    private func save() {
        switch PriceDraft.parse(harness: harness, model: modelName, input: input, output: output, cache: cache) {
        case .success(let price):
            store.savePrice(price)
            isPresented = false
        case .failure(let why): problem = why
        }
    }
}

/// Cost › New budget (`costNewBudget`): scope, target, period and a cap in dollars or tokens (API minor 18; older
/// servers: tokens, no issue scope); warn inherits the company's.
struct NewBudgetForm: View {
    let store: CitadelStore
    let model: CompanyModel
    @Binding var isPresented: Bool
    @State private var kind = "company"
    @State private var scope: String
    @State private var period = "month"
    @State private var cap = ""
    @State private var unit: BudgetUnit
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    init(store: CitadelStore, model: CompanyModel, isPresented: Binding<Bool>) {
        self.store = store
        self.model = model
        self._isPresented = isPresented
        self._scope = State(initialValue: "company:\(model.companyID)")
        self._unit = State(initialValue: store.serverSupports(minor: CitadelStore.trancheBMinor) ? .dollars : .tokens)
    }

    private var tranche: Bool { store.serverSupports(minor: CitadelStore.trancheBMinor) }

    /// Every target of the chosen kind, labelled as the budget cards read.
    private var targets: [(scope: String, label: String)] {
        switch kind {
        case "department": model.departments.map { ("department:\($0.id)", $0.name) }
        case "project": model.projects.map { ("project:\($0.id)", "\($0.key) · \($0.name)") }
        case "agent": model.agents.values.sorted { $0.name < $1.name }.map { ("agent:\($0.id)", $0.name) }
        case "issue":
            model.issues.values.filter { !["done", "cancelled"].contains($0.state) }.sorted { $0.key < $1.key }
                .map { ("issue:\($0.id)", "\($0.key) · \($0.title)") }
        default: [("company:\(model.companyID)", "Company")]
        }
    }

    var body: some View {
        let edit = BudgetEdit.parse(cap: cap, warn: "", unit: unit)
        let label = targets.first { $0.scope == scope }?.label ?? targets.first?.label ?? "Company"
        AinkradDrawerPanel(
            style: .form, onClose: { isPresented = false },
            header: { AinkradDrawerCrumb(["Cost", "New budget"], monospaced: true) }
        ) {
            AinkradDrawerSection(title: "Scope") {
                AinkradOptionGrid(
                    options: ["company", "department", "project", "agent", "issue"].map {
                        AinkradOption(
                            id: $0, title: $0.capitalized, detail: "", isEnabled: $0 != "issue" || tranche,
                            help: $0 == "issue" && !tranche ? store.help(minor: CitadelStore.trancheBMinor) : nil)
                    }, columns: 5, isOn: { $0 == kind }
                ) { picked in
                    kind = picked
                    scope = targets.first?.scope ?? ""
                }
            }
            AinkradDrawerSection(title: "Target") {
                AinkradMenuButton(
                    items: targets.map { item in
                        AinkradMenuItem(title: item.label, systemName: nil) { scope = item.scope }
                    }
                ) { Text(label) }
                .disabled(targets.count < 2)
                .fixedSize()
            }
            AinkradDrawerSection(title: "Period") {
                AinkradSegmentedPicker(items: ["day", "week", "month", "total"], selection: $period) { $0.capitalized }
                    .fixedSize()
            }
            AinkradDrawerSection(
                title: "Cap",
                hint: tranche
                    ? "dollars or tokens" : "tokens · dollar caps: \(store.help(minor: CitadelStore.trancheBMinor))"
            ) {
                if tranche {
                    AinkradSegmentedPicker(items: BudgetUnit.allCases, selection: $unit) { $0.title }.fixedSize()
                }
                AinkradTextField(text: $cap, placeholder: unit == .dollars ? "$120" : "2M").monospaced()
                if !cap.isEmpty, case .failure(let why) = edit {
                    Text(why.message).citadelFont("t11").foregroundStyle(status.danger)
                }
            }
            AinkradDrawerHint(
                "Warn at inherits the company \(model.limits["budget.warn_percent"]?.value ?? 80)% — edit it on the card to override. Counts from the start of the period."
            )
        } footer: {
            Spacer()
            AinkradDockButton("Cancel") { isPresented = false }
            AinkradDockButton("Create budget", tone: .primary, isEnabled: (try? edit.get()) != nil && !scope.isEmpty) {
                guard case .success(let edit) = edit else { return }
                store.addBudget(scope: scope, label: label, period: period, cap: edit.cap, usdCap: edit.usdCap)
                isPresented = false
            }
        }
    }
}

/// A budget edit as typed: the cap in tokens (`2M`, `900k`, `1500`) or dollars (`$900`, `1.5k`), and the warn %
/// (`nil` inherits). A dollar edit leaves `cap` 0 — the caller keeps the budget's own token cap.
struct BudgetEdit: Equatable {
    var cap: Int64
    var usdCap: Int64?
    var warnPercent: Int?

    init(cap: Int64, usdCap: Int64? = nil, warnPercent: Int?) {
        self.cap = cap
        self.usdCap = usdCap
        self.warnPercent = warnPercent
    }

    enum Problem: Error, Equatable {
        case cap, dollars, warn

        var message: String {
            switch self {
            case .cap: "The cap is a token count, 0 or more (2M, 900k)."
            case .dollars: "The cap is a dollar amount, 0 or more ($900, 1.5k)."
            case .warn: "Warn at is 50–99%, or empty to inherit."
            }
        }
    }

    static func parse(cap: String, warn: String, unit: BudgetUnit = .tokens) -> Result<BudgetEdit, Problem> {
        var tokens: Int64 = 0
        var dollars: Int64?
        switch unit {
        case .tokens:
            guard let parsed = ScopedSetting.parse(cap, unit: "tokens"), parsed >= 0 else { return .failure(.cap) }
            tokens = parsed
        case .dollars:
            guard let parsed = BudgetUnit.parseDollars(cap) else { return .failure(.dollars) }
            dollars = parsed
        }
        let typed = warn.trimmingCharacters(in: .whitespaces)
        if typed.isEmpty { return .success(BudgetEdit(cap: tokens, usdCap: dollars, warnPercent: nil)) }
        guard let percent = ScopedSetting.parse(typed, unit: "percent"), (50...99).contains(percent) else {
            return .failure(.warn)
        }
        return .success(BudgetEdit(cap: tokens, usdCap: dollars, warnPercent: Int(percent)))
    }
}
