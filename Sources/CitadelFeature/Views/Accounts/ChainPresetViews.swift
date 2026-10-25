import AinkradAppKit
import SwiftUI

/// A preset's colour: its own `#rrggbb`, else its first entry's harness colour, else the accent.
enum ChainPresetStyle {
    static func tint(_ preset: ChainPresetInfo?, skin: AinkradSkin) -> Color {
        if let rgb = CompanyLook.rgb(preset?.colorHex) {
            return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue)
        }
        return preset.flatMap { AgentLook.harness($0.harness)?.color } ?? skin.color(skin.palette.accentPrimary)
    }

    /// Every (harness, model) the hire catalog knows that `used` does not already hold: the Add fallback menu.
    static func candidates(excluding used: [FallbackEntry]) -> [FallbackEntry] {
        let taken = Set(used.map(\.id))
        return HireCatalog.harnesses.flatMap { harness in
            (HireCatalog.models[harness] ?? []).map { FallbackEntry(harness: harness, model: $0.wire) }
        }.filter { !taken.contains($0.id) }
    }
}

/// A preset as a card (`.pr-card`): letter tile in its colour, name and description, the flow, the agents on it,
/// Assign and Edit.
struct ChainPresetCard: View {
    let model: CompanyModel
    let preset: ChainPresetInfo
    let assign: () -> Void
    let edit: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = ChainPresetStyle.tint(preset, skin: skin)
        let agents = model.agents(on: preset)
        AinkradBentoTile(padding: skin.size.s12, tint: tint) {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                HStack(spacing: skin.size.s10) {
                    LetterTile(letter: String(preset.name.prefix(1)), tint: tint, size: skin.size.s32)
                    VStack(alignment: .leading, spacing: 0) {
                        HStack(spacing: skin.size.s6) {
                            Text(preset.name).citadelFont("t13", weight: "semibold").foregroundStyle(
                                skin.color(skin.text.primary))
                            if preset.isDefault { AinkradScopeChip(text: "default") }
                        }
                        Text(preset.detail).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    }
                }
                if preset.entries.isEmpty {
                    Text("Only each agent's own model").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                } else {
                    AinkradChainFlow(steps: preset.entries.map { ($0.harness, $0.model) }) {
                        HarnessTag(harness: $0, size: skin.size.s22)
                    }
                }
                HStack(spacing: skin.size.s6) {
                    AinkradAvatarStack(items: Array(agents.prefix(4)), size: skin.size.s22) {
                        AgentFigure(agent: $0, model: model, size: skin.size.s22)
                    }
                    Text(Wording.count(agents.count, "agent")).citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    Spacer(minLength: 0)
                    AinkradDockButton("Assign", systemImage: "person.2", height: skin.size.s28, action: assign)
                        .fixedSize()
                    AinkradDockButton("Edit", systemImage: "pencil", height: skin.size.s28, action: edit).fixedSize()
                }
            }
        }
    }
}

/// The dashed "＋ New preset" tile.
struct ChainPresetNewTile: View {
    let add: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        AinkradTapArea(action: add) {
            VStack(spacing: skin.size.s2) {
                Text("＋").citadelFont("t20")
                Text("New preset").citadelFont("t12")
            }
            .foregroundStyle(hovering ? skin.color(skin.text.primary) : skin.color(skin.text.faint))
            .frame(maxWidth: .infinity)
            .padding(.vertical, skin.size.s14)
            .overlay(
                shape.strokeBorder(
                    hovering
                        ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o45)
                        : skin.color(.palette("foreground", skin.opacity.o12)),
                    style: StrokeStyle(lineWidth: skin.size.s1_5, dash: [skin.size.s6, skin.size.s5]))
            )
            .contentShape(shape)
        }
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// "Uses · Codex first ▾" (`.pr-uses`): the preset an agent runs on, with the menu that changes it. `preset` nil
/// is a chain of its own; `inherited` marks the company default an agent with no chain falls to.
struct ChainPresetUses: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    let preset: ChainPresetInfo?
    let inherited: Bool
    /// What leaving the preset keeps: a copy of its fallbacks, or the agent's own.
    let current: [FallbackEntry]
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = preset.map { ChainPresetStyle.tint($0, skin: skin) } ?? skin.color(skin.palette.accentViolet)
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        AinkradMenuButton(items: items) {
            HStack(spacing: skin.size.s10) {
                LetterTile(letter: preset.map { String($0.name.prefix(1)) } ?? "✎", tint: tint, size: skin.size.s32)
                VStack(alignment: .leading, spacing: 0) {
                    Text("USES").citadelFont("t10", weight: "semibold").foregroundStyle(skin.color(skin.text.faint))
                    Text((preset?.name ?? "Custom chain") + (inherited ? " · default" : ""))
                        .citadelFont("t13", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                }
                Spacer(minLength: 0)
                Text("Change").citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                Image(systemName: "chevron.down").citadelFont("t10").foregroundStyle(skin.color(skin.text.muted))
            }
            .padding(skin.size.s10)
            .background(shape.fill(tint.opacity(skin.opacity.o10)))
            .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o28), lineWidth: 1))
        }
    }

    private var items: [AinkradMenuItem] {
        model.chainPresets.map { item in
            AinkradMenuItem(title: item.name, systemName: item.id == preset?.id && !inherited ? "checkmark" : nil) {
                store.useChainPreset(item, for: agent)
            }
        }
            + [
                AinkradMenuItem(title: "Custom chain", systemName: preset == nil ? "checkmark" : "pencil") {
                    store.customizeChain(of: agent, entries: current)
                }
            ]
    }
}

/// `acctPresetEdit`: hero, name, colour, the chain (drag, ✕, add), who uses it and "Assign…"; Done saves for all.
struct ChainPresetEditDrawer: View {
    let store: CitadelStore
    let model: CompanyModel
    /// `nil`: a new preset.
    let preset: ChainPresetInfo?
    let assign: () -> Void
    let close: @MainActor @Sendable () -> Void
    @State private var name = ""
    @State private var color: String?
    @State private var entries: [FallbackEntry] = []
    @State private var isDefault = false
    @Environment(\.ainkradSkin) private var skin

    private var draft: ChainPresetInfo {
        ChainPresetInfo(
            id: preset?.id ?? 0, name: name, description: preset?.description ?? "", colorHex: color,
            isDefault: isDefault, entries: entries)
    }

    var body: some View {
        let tint = ChainPresetStyle.tint(draft, skin: skin)
        let agents = preset.map { model.agents(on: $0) } ?? []
        AinkradDrawerPanel(
            style: .form, onClose: close,
            header: { AinkradDrawerCrumb(["Accounts", preset == nil ? "New preset" : "Preset"], monospaced: true) }
        ) {
            AinkradDrawerHero(
                tint: tint, title: name.isEmpty ? "New preset" : name,
                subtitle: entries.isEmpty
                    ? "each agent's own model only" : entries.map(\.model).joined(separator: " → ")
            ) {
                LetterTile(letter: String((name.isEmpty ? "N" : name).prefix(1)), tint: tint, size: skin.size.s52)
            } trailing: {
                EmptyView()
            }
            AinkradDrawerSection(title: "Name") { AinkradTextField(text: $name, placeholder: "Codex first") }
            AinkradDrawerSection(title: "Colour") { SettingsColorSwatches(color: $color, enabled: true) }
            AinkradDrawerSection(
                title: "Chain", hint: "after each agent's own model · drag ⋮⋮ to reorder, first entry is tried first"
            ) {
                AinkradChainEditor(
                    links: entries.map { link($0) },
                    reorder: { links in entries = links.compactMap { l in entries.first { $0.id == l.id } } },
                    remove: { l in entries.removeAll { $0.id == l.id } },
                    leading: { HarnessTag(harness: $0, size: skin.size.s20) })
                AinkradMenuButton(
                    items: ChainPresetStyle.candidates(excluding: entries).map { item in
                        AinkradMenuItem(
                            title: "\(AgentLook.harnessName(item.harness)) · \(item.model)", systemName: nil
                        ) { entries.append(item) }
                    }
                ) { Label("Add fallback", systemImage: "plus") }
                .fixedSize()
            }
            AinkradDrawerSection(title: "Default", hint: "what an agent with no chain of its own uses") {
                AinkradToggleChip(title: "Company default", isOn: isDefault, isEnabled: !(preset?.isDefault ?? false)) {
                    isDefault.toggle()
                }
            }
            if preset != nil {
                AinkradDrawerSection(title: "Used by") {
                    AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                        ForEach(agents, id: \.id) { agent in
                            HStack(spacing: skin.size.s6) {
                                AgentFigure(agent: agent, model: model, size: skin.size.s24)
                                Text(agent.name).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary))
                            }
                            .padding(.leading, skin.size.s4).padding(.trailing, skin.size.s10)
                            .frame(height: skin.size.s30)
                            .background(
                                skin.color(.palette("black", skin.opacity.o18)),
                                in: RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous))
                        }
                        AinkradDockButton("Assign…", height: skin.size.s28, action: assign).fixedSize()
                    }
                }
            }
        } footer: {
            if let preset {
                AinkradDockButton("Delete", tone: .danger) { store.deleteChainPreset(preset, done: close) }
            }
            Spacer()
            AinkradDockButton("Cancel", action: close)
            AinkradDockButton(
                preset == nil ? "Create preset" : "Done", tone: .primary,
                isEnabled: !name.trimmingCharacters(in: .whitespaces).isEmpty
            ) {
                store.saveChainPreset(draft, isNew: preset == nil) { _ in close() }
            }
        }
        .onAppear {
            name = preset?.name ?? ""
            color = preset?.colorHex
            entries = preset?.entries ?? []
            isDefault = preset?.isDefault ?? false
        }
    }

    private func link(_ entry: FallbackEntry) -> AinkradChainLink {
        let pin = entry.accountID.flatMap { model.accounts[$0]?.label }
        return AinkradChainLink(
            id: entry.id, kind: entry.harness, title: entry.model,
            detail: pin.map { "account: \($0)" } ?? "account: any in the pool")
    }
}

/// `acctAssign`: the agents as cards with the preset each is on; Assign to N.
struct ChainPresetAssignDrawer: View {
    let store: CitadelStore
    let model: CompanyModel
    let preset: ChainPresetInfo
    let close: @MainActor @Sendable () -> Void
    @State private var picked: Set<Int64> = []
    @Environment(\.ainkradSkin) private var skin

    private var agents: [AgentInfo] { model.agents.values.filter { !$0.isHirePending }.sorted { $0.name < $1.name } }

    var body: some View {
        let tint = ChainPresetStyle.tint(preset, skin: skin)
        AinkradDrawerPanel(
            style: .form, onClose: close,
            header: { AinkradDrawerCrumb(["Accounts", preset.name, "Assign"], monospaced: true) }
        ) {
            AinkradDrawerHero(
                tint: tint, title: "\(picked.count) of \(agents.count) agents",
                subtitle: "will use \(preset.name) from their next run"
            ) {
                LetterTile(letter: String(preset.name.prefix(1)), tint: tint, size: skin.size.s52)
            } trailing: {
                EmptyView()
            }
            if !preset.entries.isEmpty {
                AinkradChainFlow(steps: preset.entries.map { ($0.harness, $0.model) }) {
                    HarnessTag(harness: $0, size: skin.size.s22)
                }
            }
            AinkradCardGrid(columns: 2) {
                ForEach(agents) { agent in
                    PersonCard(model: model, agent: agent, line: line(agent), isOn: picked.contains(agent.id)) {
                        if !picked.insert(agent.id).inserted { picked.remove(agent.id) }
                    }
                }
            }
            AinkradDrawerHint("Agents that were on it and are left out keep a copy as a chain of their own.")
        } footer: {
            AinkradDockButton(picked.count == agents.count ? "Select none" : "Select all") {
                picked = picked.count == agents.count ? [] : Set(agents.map(\.id))
            }
            Spacer()
            AinkradDockButton("Cancel", action: close)
            AinkradDockButton("Assign to \(picked.count)", tone: .primary) {
                store.assign(preset, to: picked, done: close)
            }
        }
        .onAppear { picked = Set(model.agents(on: preset).map(\.id)) }
    }

    /// "Dev · Codex first": the agent's role and the preset it is on now.
    private func line(_ agent: AgentInfo) -> String {
        let now = model.chainPreset(of: agent, fallbacks: model.accountsPage.agentFallbacks[agent.id])
        return [agent.roleLabel, now?.name ?? "own chain"].joined(separator: " · ")
    }
}
