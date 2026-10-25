import AinkradAppKit
import SwiftUI

/// Settings (prototype `agent.js` agentSettings): Model, Fallback chain, Budget, Access, Look, Danger. What the
/// API backs applies at once with a toast (Look, Budget). Model, Access and About save with PATCH /agents/{id}
/// (API minor 17); an older server keeps their Save off with a "needs a server update" line.
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
    @State private var unit = BudgetUnit.tokens
    @State private var warn = "80"
    @State private var cap = ""
    @State private var about = ""
    @State private var boss: Int64?
    @Environment(\.ainkradSkin) private var skin

    private var supported: Bool { store.serverSupports(minor: CitadelStore.structureMinor) }
    private var modelChanged: Bool {
        harness != agent.harness || wire != agent.model || effort != (agent.effort ?? "medium")
    }
    private var accessChanged: Bool {
        sandbox != (agent.sandbox ?? "workspace-write") || tags != Set(agent.runnerTags) || boss != agent.reportsTo
    }

    /// Who it may report to: anyone seated and active who is not under it (that would be a loop).
    private var bosses: [AgentInfo] {
        var below = Set<Int64>([agent.id])
        var queue = [agent.id]
        while let next = queue.popLast() {
            for report in model.reports(of: next) where below.insert(report.id).inserted { queue.append(report.id) }
        }
        return model.agents.values.filter { !below.contains($0.id) && $0.status == "active" }.sorted { $0.id < $1.id }
    }

    private func saveRow(_ title: String, changed: Bool, save: @escaping () -> Void) -> some View {
        HStack {
            if !supported { NeedsServer(text: CitadelStore.needsServerUpdate) }
            Spacer()
            AinkradButton(title: title, action: save).compact().fixedSize()
                .disabled(!supported || !changed)
                .help(store.help(ready: "Saves with PATCH /agents/{id}"))
        }
    }

    var body: some View {
        let page = model.orgPage
        DrawerTile(title: "Model") {
            HarnessCards(model: model, selection: $harness)
            ModelCards(harness: harness, selection: $wire)
            EffortCards(selection: $effort)
            saveRow("Save model", changed: modelChanged) {
                store.edit(
                    agent, AgentPatch(harness: harness, model: wire, effort: effort), title: "Model updated",
                    body: "Applies from the next run.")
            }
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
            if store.serverSupports(minor: CitadelStore.trancheBMinor) {
                AinkradSegmentedPicker(items: BudgetUnit.allCases, selection: $unit) { $0.title }.fixedSize()
            }
            if unit == .dollars {
                AinkradFormRow(title: "Monthly budget", help: "Dollars a month: $120, 1.5k.") {
                    AinkradTextField(text: $budget, placeholder: "$120").monospaced()
                }
            } else {
                BudgetFields(budget: $budget, warn: $warn, cap: $cap)
            }
            HStack {
                NeedsServer(text: "The per-run cap is set per company or project; an agent scope needs the server.")
                Spacer()
                AinkradButton(title: "Save budget") {
                    if let caps = BudgetUnit.parseCap(budget, unit: unit) {
                        store.setMonthBudget(
                            agent, cap: caps.cap, usdCap: caps.usdCap,
                            warnPercent: Int(warn).map { min(99, max(1, $0)) })
                    }
                }
                .compact().fixedSize()
                .disabled(BudgetUnit.parseCap(budget, unit: unit) == nil)
            }
        }
        .onChange(of: unit) { _, now in
            let month = model.monthBudget(of: agent.id)
            budget = month?.unit == now ? month?.capWord ?? "" : ""
        }
        .id("budget")
        DrawerTile(title: "Access") {
            SandboxCards(selection: $sandbox)
            RunnerTagCards(model: model, selection: $tags)
            Text("Reports to").citadelFont("t11", weight: "medium").foregroundStyle(skin.color(skin.text.muted))
            AinkradCardGrid(columns: 4) {
                ForEach(bosses) { person in
                    PersonCard(model: model, agent: person, line: model.title(of: person), isOn: boss == person.id) {
                        boss = person.id
                    }
                }
            }
            saveRow("Save access", changed: accessChanged) {
                store.edit(
                    agent,
                    AgentPatch(
                        sandbox: sandbox, runnerTags: tags.sorted(),
                        reportsTo: boss != agent.reportsTo ? boss : nil), title: "Access updated",
                    body: "Applies from the next run.")
            }
        }
        .id("access")
        DrawerTile(title: "About") {
            AinkradTextArea(
                text: $about, placeholder: "What this agent is for — shown on its profile", minHeight: skin.size.s60)
            saveRow("Save description", changed: about != (agent.about ?? "")) {
                store.edit(agent, AgentPatch(about: about), title: "Description saved")
            }
        }
        .id("about")
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
            effort = agent.effort ?? "medium"
            sandbox = agent.sandbox ?? "workspace-write"
            about = agent.about ?? ""
            boss = agent.reportsTo
            let month = model.monthBudget(of: agent.id)
            unit = month?.unit ?? .tokens
            budget = month?.capWord ?? ""
            warn = "\(month?.warnPercent ?? Int(model.warnFraction * 100))"
            cap = model.runCap.map(Fmt.tokens) ?? ""
        }
    }
}
