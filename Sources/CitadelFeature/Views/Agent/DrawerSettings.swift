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

    /// The model edit a pick makes, or `nil` when nothing changed or the harness and model do not belong together
    /// yet (a new harness keeps the old model until one of its own is picked).
    static func modelPatch(harness: String, wire: String, effort: String, agent: AgentInfo) -> AgentPatch? {
        let pairChanged = harness != agent.harness || wire != agent.model
        guard pairChanged || effort != (agent.effort ?? "medium") else { return nil }
        if pairChanged, HireCatalog.models[harness]?.contains(where: { $0.wire == wire }) != true { return nil }
        return AgentPatch(harness: harness, model: wire, effort: effort)
    }

    private func applyAccess() {
        guard supported, accessChanged else { return }
        store.edit(
            agent,
            AgentPatch(sandbox: sandbox, runnerTags: tags.sorted(), reportsTo: boss != agent.reportsTo ? boss : nil),
            title: "Access updated", body: "Applies from the next run.")
    }

    var body: some View {
        let page = model.orgPage
        DrawerTile(title: "Model") {
            HarnessCards(model: model, selection: $harness)
            ModelCards(harness: harness, selection: $wire)
            EffortCards(selection: $effort)
            if !supported { NeedsServer(text: CitadelStore.needsServerUpdate) }
        }
        .onChange(of: [harness, wire, effort]) { _, _ in
            guard supported,
                let patch = Self.modelPatch(harness: harness, wire: wire, effort: effort, agent: agent)
            else { return }
            store.edit(agent, patch, title: "Model updated", body: "Applies from the next run.")
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
            let stored = page.chains[agent.id] ?? []
            let preset = store.chainPresetsOn ? model.chainPreset(of: agent, fallbacks: stored) : nil
            let chain = preset?.entries ?? stored
            if store.chainPresetsOn {
                ChainPresetUses(
                    store: store, model: model, agent: agent, preset: preset,
                    inherited: preset != nil && agent.chainPresetID == nil, current: chain)
            }
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
        .task { store.loadChainPresets() }
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
                BudgetFields(budget: $budget, warn: $warn, cap: $cap, capEnabled: false)
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
            if !supported { NeedsServer(text: CitadelStore.needsServerUpdate) }
        }
        .onChange(of: sandbox) { _, _ in applyAccess() }
        .onChange(of: tags) { _, _ in applyAccess() }
        .onChange(of: boss) { _, _ in applyAccess() }
        .id("access")
        DrawerTile(title: "About") {
            AinkradTextArea(
                text: $about, placeholder: "What this agent is for — shown on its profile", minHeight: skin.size.s60)
            if !supported { NeedsServer(text: CitadelStore.needsServerUpdate) }
        }
        // The text area has no blur callback; leaving the drawer or its tab is the blur.
        .onDisappear {
            if supported, about != (agent.about ?? "") {
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
