import AinkradAppKit
import SwiftUI

/// "Fallback chains" (`chainPanel`): Presets — the chains several agents share, each editable for all of them — and
/// Agents — one agent's chain, drag to reorder, ✕ to remove, + Add fallback; then the company's "Fall back when"
/// triggers. From API minor 18 the presets are the server's (name, colour, assign, new, default); an older server
/// keeps the chains agents happen to share.
struct FallbackChainsCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let editChain: (String) -> Void
    @Environment(\.ainkradSkin) private var skin

    private var tab: String { page.chainsTab }
    /// The server stores named presets (API minor 18).
    private var named: Bool { store.chainPresetsOn }

    private var page: AccountsPage { model.accountsPage }
    private var agents: [AgentInfo] { model.agents.values.filter { !$0.isHirePending }.sorted { $0.name < $1.name } }

    var body: some View {
        let shared = page.sharedChains(agents)
        AinkradBentoTile(padding: skin.size.s14) {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                Text("Fallback chains").citadelFont("t13", weight: "bold").foregroundStyle(
                    skin.color(skin.text.primary))
                AinkradGlideTabs(
                    [
                        AinkradGlideTab(
                            "presets", title: "Presets", count: "\(named ? model.chainPresets.count : shared.count)"),
                        AinkradGlideTab("agents", title: "Agents", count: "\(agents.count)"),
                    ], selection: Binding(get: { tab }, set: { page.chainsTab = $0 }), height: skin.size.s32)
                Group {
                    if tab == "presets" {
                        if named { namedPresets } else { presets(shared) }
                    } else {
                        agentChain(shared)
                    }
                }
                .transition(.opacity)
                Text("Fall back when").citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                    .padding(.top, skin.size.s4)
                AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                    ForEach(AccountsPage.triggers, id: \.key) { trigger in
                        let setting = page.companySettings[trigger.key]
                        let isOn = (setting?.value ?? 1) == 1
                        AinkradToggleChip(
                            title: trigger.title, isOn: isOn, isEnabled: setting != nil,
                            help: setting?.description ?? "Not read from the server yet"
                        ) {
                            store.setFallbackTrigger(trigger.key, title: trigger.title, on: !isOn)
                        }
                    }
                }
            }
        }
    }

    /// The server's presets: a card each, then "＋ New preset".
    @ViewBuilder private var namedPresets: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            if model.chainPresets.isEmpty {
                AinkradDrawerHint("No presets yet — create one to share a chain between agents.")
            }
            ForEach(model.chainPresets) { preset in
                ChainPresetCard(
                    model: model, preset: preset, assign: { page.drawer = .assign(preset.id) },
                    edit: { page.drawer = .preset(preset.id) })
            }
            ChainPresetNewTile { page.drawer = .preset(nil) }
        }
    }

    @ViewBuilder private func presets(_ shared: [SharedChain]) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            if shared.isEmpty {
                AinkradDrawerHint("No two agents share a chain yet — each one's chain is on the Agents tab.")
            }
            ForEach(Array(shared.enumerated()), id: \.element.id) { _, chain in
                PresetCard(model: model, chain: chain) { editChain(chain.id) }
            }
            NewPresetTile()
        }
    }

    @ViewBuilder private func agentChain(_ shared: [SharedChain]) -> some View {
        if let id = page.chainAgent ?? agents.first?.id, let agent = model.agent(id) {
            let mine = shared.first { $0.agents.contains(id) }
            VStack(alignment: .leading, spacing: skin.size.s10) {
                AinkradMenuButton(
                    items: agents.map { other in
                        AinkradMenuItem(title: other.nameDotRole, systemName: nil) { store.showChain(of: other.id) }
                    }
                ) {
                    HStack(spacing: skin.size.s10) {
                        AgentFigure(agent: agent, model: model, size: skin.size.s30)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("AGENT").citadelFont("t10", weight: "semibold").foregroundStyle(
                                skin.color(skin.text.faint))
                            Text(agent.nameDotRole).citadelFont("t13", weight: "semibold")
                                .foregroundStyle(skin.color(skin.text.primary))
                        }
                        Spacer(minLength: 0)
                    }
                }
                if named { namedAgentChain(agent) } else { UsesRow(chain: mine) }
                if !named || usedPreset(agent) == nil {
                    AinkradChainEditor(
                        links: links(agent), editable: true,
                        reorder: { store.saveChain(entries($0)) },
                        remove: { link in store.saveChain(page.chain.filter { $0.id != link.id }) },
                        leading: { HarnessTag(harness: $0, size: skin.size.s20) })
                    addFallback
                    if named {
                        AinkradDockButton("Save as preset", systemImage: "square.and.arrow.down") {
                            store.savePresetFromChain(of: agent, entries: page.chain)
                        }
                        .fixedSize()
                    }
                }
                if !named, let mine {
                    AinkradDrawerHint(
                        "Same chain as \(Wording.count(mine.agents.count - 1, "other agent")) — edit \(mine.name) on Presets to change it for all of them."
                    )
                }
            }
        }
    }

    /// The preset the picked agent runs on (its own, else the default while it has no chain), from API minor 18.
    private func usedPreset(_ agent: AgentInfo) -> ChainPresetInfo? {
        model.chainPreset(of: agent, fallbacks: page.agentFallbacks[agent.id])
    }

    /// "Uses" with its menu; on a preset the read-only chain, who shares it, Edit preset and Customize.
    @ViewBuilder private func namedAgentChain(_ agent: AgentInfo) -> some View {
        let preset = usedPreset(agent)
        ChainPresetUses(
            store: store, model: model, agent: agent, preset: preset,
            inherited: preset != nil && agent.chainPresetID == nil,
            current: preset?.entries ?? page.chain)
        if let preset {
            AinkradChainEditor(
                links: [
                    AinkradChainLink(
                        id: "own", kind: agent.harness, title: agent.model, detail: "the agent's own harness and model",
                        chip: "first", isCurrent: true, isFixed: true)
                ]
                    + preset.entries.map {
                        AinkradChainLink(
                            id: $0.id, kind: $0.harness, title: $0.model,
                            detail: $0.accountID.flatMap { model.accounts[$0]?.label }.map { "account: \($0)" }
                                ?? "account: any in the pool")
                    }, editable: false, leading: { HarnessTag(harness: $0, size: skin.size.s20) })
            let others = model.agents(on: preset).filter { $0.id != agent.id }.count
            AinkradDrawerHint(
                others > 0
                    ? "Shared with \(Wording.count(others, "other agent")) — editing the preset changes it for all of them."
                    : "Editing the preset changes it for every agent on it.")
            HStack(spacing: skin.size.s8) {
                AinkradDockButton("Edit preset", systemImage: "pencil") { page.drawer = .preset(preset.id) }.fixedSize()
                AinkradDockButton("Customize for \(agent.name)", systemImage: "slider.horizontal.3") {
                    store.customizeChain(of: agent, entries: preset.entries)
                }
                .fixedSize()
            }
        }
    }

    private func links(_ agent: AgentInfo) -> [AinkradChainLink] {
        let live = model.liveRuns.first { $0.agentID == agent.id }
        let current = live.map { "\($0.harness)|\($0.model ?? "")" }
        return page.chain.map { entry in
            AinkradChainLink(
                id: entry.id, kind: entry.harness, title: entry.model,
                detail: (entry.isOwn ? "the agent's own harness and model" : "account: pool")
                    + (entry.harness == "opencode" ? " · unpriced" : ""),
                detailWarns: entry.harness == "opencode",
                chip: entry.id == current ? "serving" : entry.isOwn ? "first" : nil,
                isCurrent: entry.id == current || (current == nil && entry.isOwn), isFixed: entry.isOwn)
        }
    }

    private func entries(_ links: [AinkradChainLink]) -> [FallbackEntry] {
        links.compactMap { link in page.chain.first { $0.id == link.id } }
    }

    /// "+ Add fallback": a (harness, model) another agent of the company runs on.
    @ViewBuilder private var addFallback: some View {
        let used = Set(page.chain.map(\.id))
        let candidates = Set(model.agents.values.map { "\($0.harness)|\($0.model)" }).subtracting(used).sorted()
        AinkradMenuButton(
            items: candidates.map { id in
                let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
                return AinkradMenuItem(
                    title: "\(AgentLook.harnessName(parts[0])) · \(parts.last ?? "")", systemName: nil
                ) {
                    store.saveChain(page.chain + [FallbackEntry(harness: parts[0], model: parts.last ?? "")])
                    store.toast(
                        AinkradRichToast(
                            title: "\(parts.last ?? "") added", body: "Entry \(page.chain.count + 1)", status: .success)
                    )
                }
            }
        ) { Label("Add fallback", systemImage: "plus") }
        .disabled(candidates.isEmpty || page.chainAgent == nil)
        .fixedSize()
    }
}

/// A shared chain as a preset card (`.pr-card`): letter tile, name, models; the flow; its agents; Edit.
private struct PresetCard: View {
    let model: CompanyModel
    let chain: SharedChain
    let edit: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = AgentLook.harness(chain.harness)?.color ?? skin.color(skin.palette.accentPrimary)
        let agents = chain.agents.compactMap { model.agent($0) }
        AinkradBentoTile(padding: skin.size.s12, tint: tint) {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                HStack(spacing: skin.size.s10) {
                    LetterTile(letter: String(chain.name.prefix(1)), tint: tint, size: skin.size.s32)
                    VStack(alignment: .leading, spacing: 0) {
                        Text(chain.name).citadelFont("t13", weight: "semibold").foregroundStyle(
                            skin.color(skin.text.primary))
                        Text(chain.detail).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    }
                }
                AinkradChainFlow(steps: chain.entries.map { ($0.harness, $0.model) }) {
                    HarnessTag(harness: $0, size: skin.size.s22)
                }
                HStack(spacing: skin.size.s6) {
                    AinkradAvatarStack(items: Array(agents.prefix(4)), size: skin.size.s22) {
                        AgentFigure(agent: $0, model: model, size: skin.size.s22)
                    }
                    Text(Wording.count(agents.count, "agent")).citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    Spacer(minLength: 0)
                    AinkradDockButton("Assign", systemImage: "person.2", isEnabled: false, height: skin.size.s28) {}
                        .fixedSize()
                        .help("Assigning a preset needs the server's chain presets")
                    AinkradDockButton("Edit", systemImage: "pencil", height: skin.size.s28, action: edit)
                        .fixedSize()
                }
            }
        }
    }
}

/// The dashed "＋ New preset" tile — disabled until the server stores named presets.
private struct NewPresetTile: View {
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        VStack(spacing: skin.size.s2) {
            Text("＋").citadelFont("t20")
            Text("New preset").citadelFont("t12")
            Text("needs the server's chain presets").citadelFont("t10_5")
        }
        .foregroundStyle(skin.color(skin.text.faint))
        .frame(maxWidth: .infinity)
        .padding(.vertical, skin.size.s14)
        .overlay(
            shape.strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o12)),
                style: StrokeStyle(lineWidth: skin.size.s1_5, dash: [skin.size.s6, skin.size.s5]))
        )
        .help("Named presets (name, colour, assign) need the server's chain-presets entity")
    }
}

/// "Uses · Codex first" / "Uses · Custom chain" (`.pr-uses`).
private struct UsesRow: View {
    let chain: SharedChain?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = chain.flatMap { AgentLook.harness($0.harness)?.color } ?? skin.color(skin.palette.accentViolet)
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        HStack(spacing: skin.size.s10) {
            LetterTile(letter: chain.map { String($0.name.prefix(1)) } ?? "✎", tint: tint, size: skin.size.s32)
            VStack(alignment: .leading, spacing: 0) {
                Text("USES").citadelFont("t10", weight: "semibold").foregroundStyle(skin.color(skin.text.faint))
                Text(chain?.name ?? "Custom chain").citadelFont("t13", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.primary))
            }
            Spacer(minLength: 0)
        }
        .padding(skin.size.s10)
        .background(shape.fill(tint.opacity(skin.opacity.o10)))
        .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o28), lineWidth: 1))
    }
}

/// `.pr-ic`: a letter on a solid colour tile with a glow.
struct LetterTile: View {
    let letter: String
    let tint: Color
    let size: CGFloat
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(letter).citadelFont(size > skin.size.s40 ? "t21" : "t14", weight: "bold")
            .foregroundStyle(skin.color(.palette("background", 1)))
            .frame(width: size, height: size)
            .background(tint, in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
            .shadow(color: tint.opacity(skin.opacity.o35), radius: size * 0.22, y: size * 0.12)
    }
}

/// Editing a shared chain (`acctPresetEdit`): hero, the chain (drag / ✕ / add), who uses it; Done saves for all.
struct SharedChainDrawer: View {
    let store: CitadelStore
    let model: CompanyModel
    let chain: SharedChain
    let close: () -> Void
    @State private var entries: [FallbackEntry] = []
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = AgentLook.harness(chain.harness)?.color ?? skin.color(skin.palette.accentPrimary)
        AinkradDrawerPanel(
            style: .form, onClose: close, header: { AinkradDrawerCrumb(["Accounts", "Preset"], monospaced: true) }
        ) {
            AinkradDrawerHero(tint: tint, title: chain.name, subtitle: chain.detail) {
                LetterTile(letter: String(chain.name.prefix(1)), tint: tint, size: skin.size.s52)
            } trailing: {
                EmptyView()
            }
            AinkradDrawerSection(title: "Name", hint: "named presets need the server") {
                Text(chain.name).citadelFont("t13", mono: true).foregroundStyle(skin.color(skin.text.muted))
            }
            AinkradDrawerSection(
                title: "Chain", hint: "drag ⋮⋮ to reorder · first entry serves, the rest are fallbacks"
            ) {
                AinkradChainEditor(
                    links: entries.map {
                        AinkradChainLink(
                            id: $0.id, kind: $0.harness, title: $0.model,
                            detail: $0.isOwn ? "each agent's own harness and model" : "account: pool",
                            chip: $0.isOwn ? "first" : nil, isCurrent: $0.isOwn, isFixed: $0.isOwn)
                    },
                    reorder: { links in entries = links.compactMap { link in entries.first { $0.id == link.id } } },
                    remove: { link in entries.removeAll { $0.id == link.id } },
                    leading: { HarnessTag(harness: $0, size: skin.size.s20) })
            }
            AinkradDrawerSection(title: "Used by") {
                AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                    ForEach(chain.agents.compactMap { model.agent($0) }, id: \.id) { agent in
                        HStack(spacing: skin.size.s6) {
                            AgentFigure(agent: agent, model: model, size: skin.size.s24)
                            Text(agent.name).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary))
                        }
                        .padding(.leading, skin.size.s4)
                        .padding(.trailing, skin.size.s10)
                        .frame(height: skin.size.s30)
                        .background(
                            skin.color(.palette("black", skin.opacity.o18)),
                            in: RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous))
                    }
                }
            }
        } footer: {
            Spacer()
            AinkradDockButton("Cancel", action: close)
            AinkradDockButton("Done", tone: .primary) {
                store.saveSharedChain(chain, fallbacks: entries.filter { !$0.isOwn })
                close()
            }
        }
        .onAppear { entries = chain.entries }
    }
}
