import AinkradAppKit
import SwiftUI

/// Settings (prototype `agent.js` agentSettings): Model, Fallback chain, Budget, Access, Look, Danger. What the
/// API backs applies at once with a toast (Look, Budget); the rest is drawn and marked "needs server".
struct DrawerSettings: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @State private var harness = ""
    @State private var wire = ""
    @State private var effort = "medium"
    @State private var sandbox = "workspace-write"
    @State private var tags: Set<String> = []
    @State private var budget = ""
    @State private var warn = "80"
    @State private var cap = ""
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let page = model.orgPage
        DrawerTile(title: "Model") {
            HarnessCards(model: model, selection: $harness)
            ModelCards(harness: harness, selection: $wire)
            EffortCards(selection: $effort)
            NeedsServer(text: "Changing harness, model or effort needs PATCH /agents/{id}; the cards show its setup.")
        }
        .id("model")
        DrawerTile(
            title: "Fallback chain",
            link: (
                "Manage in Accounts →",
                {
                    store.showChain(of: agent.id)
                    store.screen = .accounts
                    store.detail = nil
                }
            )
        ) {
            Text(
                "When \(agent.name)'s model or account can't take the run (rate limit, quota, outage), it moves down this list."
            )
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            let chain = page.chains[agent.id] ?? []
            if chain.isEmpty {
                Text("Its own model only.").citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            }
            ForEach(Array(chain.enumerated()), id: \.element.id) { index, entry in
                HStack(spacing: skin.size.s10) {
                    Text("\(index + 1)").citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
                        .frame(width: skin.size.s14)
                    HarnessTag(harness: entry.harness, size: skin.size.s20)
                    Text(HireCatalog.modelName(entry.model)).citadelFont("t12", weight: "medium")
                    Spacer()
                    if entry.isOwn { Text("own").citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint)) }
                }
                .padding(.horizontal, skin.size.s10).frame(height: skin.size.s34)
                .background(
                    skin.color(.palette("foreground", skin.opacity.o05)),
                    in: RoundedRectangle(cornerRadius: skin.size.s8))
            }
        }
        .id("chain")
        DrawerTile(title: "Budget") {
            BudgetFields(budget: $budget, warn: $warn, cap: $cap)
            HStack {
                NeedsServer(text: "The per-run cap is set per company or project; an agent scope needs the server.")
                Spacer()
                AinkradButton(title: "Save budget") {
                    if let tokens = TokenAmount.parse(budget), tokens > 0 {
                        store.setMonthBudget(agent, cap: tokens, warnPercent: Int(warn).map { min(99, max(1, $0)) })
                    }
                }
                .compact().fixedSize()
                .disabled((TokenAmount.parse(budget) ?? 0) <= 0)
            }
        }
        .id("budget")
        DrawerTile(title: "Access") {
            SandboxCards(selection: $sandbox)
            RunnerTagCards(model: model, selection: $tags)
            NeedsServer(text: "Sandbox and runner tags change with PATCH /agents/{id}.")
        }
        .id("access")
        DrawerTile(title: "Look") {
            PaletteGrid(
                selection: Binding(
                    get: { model.agents[agent.id]?.paletteID ?? agent.paletteID },
                    set: { store.setPalette(agent, $0) }))
        }
        .id("look")
        DrawerTile(title: "", danger: true) {
            HStack(spacing: skin.size.s12) {
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text("Terminate \(agent.name)").citadelFont("t13", weight: "semibold")
                    Text("Runs stop, issues return to the team queue, history stays readable.").citadelFont("t12")
                        .foregroundStyle(skin.color(skin.text.muted))
                }
                Spacer()
                AinkradButton(title: "Terminate…", style: .danger) { page.sheet = .terminate(agent.id) }.fixedSize()
            }
        }
        .onAppear {
            harness = agent.harness
            wire = agent.model
            tags = Set(agent.runnerTags)
            let month = model.monthBudget(of: agent.id)
            budget = month.map { Fmt.tokens($0.cap) } ?? ""
            warn = "\(month?.warnPercent ?? Int(model.warnFraction * 100))"
            cap = model.runCap.map(Fmt.tokens) ?? ""
        }
    }
}
