import AinkradAppKit
import AppKit
import SwiftUI

/// The agent ⋯ menu (prototype `agent-actions.js` MENUS.agentMore): the org's right-click and the agent page.
enum AgentMenu {
    @MainActor
    static func items(store: CitadelStore, model: CompanyModel, agent: AgentInfo) -> [AinkradMenuItem] {
        let page = model.orgPage
        let live = model.currentRun(of: agent.id).flatMap { $0.isLive ? $0 : nil }
        var items: [AinkradMenuItem] = [
            AinkradMenuItem(title: "Chat", systemName: "bubble.left") { store.chat(with: agent.id) },
            live.map { run in
                AinkradMenuItem(title: "Open live run", systemName: "play") { store.open(.run(run.id)) }
            } ?? AinkradMenuItem(title: "Open profile", systemName: "person") { store.open(.agent(agent.id)) },
            AinkradMenuItem(title: "Edit budget…", systemName: "dollarsign.circle") {
                page.sheet = .editBudget(agent.id)
            }.startingGroup(),
            AinkradMenuItem(title: "Change model…", systemName: "cpu") { page.sheet = .changeModel(agent.id) },
            AinkradMenuItem(title: "Appearance…", systemName: "paintpalette") { page.sheet = .appearance(agent.id) },
        ]
        if !model.openWork(of: agent.id).isEmpty {
            items.append(
                AinkradMenuItem(title: "Reassign its work…", systemName: "arrowshape.turn.up.right") {
                    page.sheet = .reassign(agent.id)
                })
        }
        items.append(
            AinkradMenuItem(title: "Copy agent id", systemName: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(agent.id), forType: .string)
                store.toast(AinkradRichToast(title: "Copied", body: "agent \(agent.id)"))
            })
        if !agent.isHirePending {
            items.append(
                (agent.isPaused
                    ? AinkradMenuItem(title: "Resume", systemName: "play") { store.resume(agent) }
                    : AinkradMenuItem(title: "Pause", systemName: "pause") { page.sheet = .pause(agent.id) })
                    .startingGroup())
        }
        if let live {
            items.append(
                AinkradMenuItem(title: "Stop run now", systemName: "stop", isDestructive: true) {
                    page.sheet = .stopRun(live.id)
                })
        }
        items.append(
            AinkradMenuItem(title: "Terminate agent…", systemName: "xmark.circle", isDestructive: true) {
                page.sheet = .terminate(agent.id)
            })
        return items
    }
}

/// "Edit budget…" (440): the month cap in tokens, its source; Save sets or creates the agent's budget.
struct EditBudgetSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @State private var text = ""
    @State private var problem: String?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let budget = model.monthBudget(of: agent.id)
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("\(agent.name)'s monthly budget").citadelFont("t15", weight: "semibold")
            Text(
                "Warns at \(budget?.warnPercent ?? Int(model.warnFraction * 100))%; at 100% new runs stop until next month or a raise. \(Fmt.tokens(budget?.spent ?? 0)) tokens used this month."
            )
            .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted)).fixedSize(
                horizontal: false, vertical: true)
            AinkradFormRow(title: "Budget", help: "Tokens a month: 8M, 500k or 8000000.") {
                AinkradTextField(text: $text, placeholder: budget.map { Fmt.tokens($0.cap) } ?? "8M").monospaced()
            }
            AinkradFormRow(title: "Source") {
                Text(budget == nil ? "none yet — Save adds an agent budget" : "● agent override")
                    .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            }
            if let problem { Text(problem).citadelFont("t12").foregroundStyle(skin.color(skin.palette.danger)) }
            SheetButtons(confirm: "Save") {
                guard let cap = TokenAmount.parse(text), cap > 0 else {
                    problem = "Enter a positive amount of tokens."
                    return false
                }
                store.setMonthBudget(agent, cap: cap, warnPercent: budget?.warnPercent)
                return true
            } cancel: {
                model.orgPage.sheet = nil
            }
        }
        .onAppear { text = model.monthBudget(of: agent.id).map { Fmt.tokens($0.cap) } ?? "" }
    }
}

/// "Change model…" (520): harness, model, effort, saved with `PATCH /agents/{id}` (API minor 17); an older server
/// keeps Save off and says so.
struct ChangeModelSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @State private var harness = ""
    @State private var wire = ""
    @State private var effort = "medium"
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Change \(agent.name)'s model").citadelFont("t15", weight: "semibold")
            Text("Applies from the next run; the current run keeps its model.").citadelFont("t12")
                .foregroundStyle(skin.color(skin.text.muted))
            AinkradFormRow(title: "Harness") {
                AinkradSegmentedPicker(items: HireCatalog.harnesses, selection: $harness) { AgentLook.harnessName($0) }
                    .fixedSize()
            }
            AinkradFormRow(title: "Model") {
                AinkradSegmentedPicker(items: (HireCatalog.models[harness] ?? []).map(\.wire), selection: $wire) {
                    HireCatalog.modelName($0)
                }
                .fixedSize()
            }
            AinkradFormRow(title: "Effort") {
                AinkradSegmentedPicker(items: HireCatalog.efforts.map(\.id), selection: $effort) { $0 }.fixedSize()
            }
            if !store.serverSupports(minor: CitadelStore.structureMinor) {
                NeedsServer(text: CitadelStore.needsServerUpdate)
            }
            SheetButtons(confirm: "Save", enabled: store.serverSupports(minor: CitadelStore.structureMinor)) {
                store.edit(
                    agent, AgentPatch(harness: harness, model: wire, effort: effort), title: "Model updated",
                    body: "Applies from the next run.")
                return true
            } cancel: {
                model.orgPage.sheet = nil
            }
        }
        .onAppear {
            harness = agent.harness
            wire = agent.model
            effort = agent.effort ?? "medium"
        }
        .onChange(of: harness) { _, new in
            if new != agent.harness { wire = HireCatalog.models[new]?.first?.wire ?? "" }
        }
    }
}

/// "Appearance…" (620): every palette as a 48 pt figure; Use palette recolours the agent everywhere.
struct AppearanceSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @State private var picked = ""
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("\(agent.name)'s appearance").citadelFont("t15", weight: "semibold")
            Text("The Orb's palette — picked at hire, shown everywhere this agent appears.").citadelFont("t12")
                .foregroundStyle(skin.color(skin.text.muted))
            CardGrid(columns: 6) {
                ForEach(AinkradFigurePalette.all) { palette in
                    VStack(spacing: skin.size.s4) {
                        AinkradAgentFigure(
                            name: agent.name, state: .idle, palette: palette, harness: agent.figureHarness,
                            size: skin.size.s48)
                        Text(palette.name).citadelFont("t10_5").lineLimit(1)
                    }
                    .foregroundStyle(picked == palette.id ? skin.color(skin.text.primary) : skin.color(skin.text.muted))
                    .padding(.vertical, skin.size.s8)
                    .frame(maxWidth: .infinity)
                    .background(
                        RoundedRectangle(cornerRadius: skin.size.s10).fill(
                            picked == palette.id
                                ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o30) : .clear)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { picked = palette.id }
                }
            }
            SheetButtons(confirm: "Use palette") {
                store.setPalette(agent, picked)
                return true
            } cancel: {
                model.orgPage.sheet = nil
            }
        }
        .onAppear { picked = agent.paletteID }
    }
}

/// "Reassign its work…" (520): its open issues and the same-role agents to move them to.
struct ReassignSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @State private var target: Int64 = 0
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let work = model.openWork(of: agent.id)
        let peers = model.agents.values.filter {
            $0.role.lowercased() == agent.role.lowercased() && $0.id != agent.id && !$0.isHirePending
        }.sorted { $0.name < $1.name }
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Reassign \(agent.name)'s work").citadelFont("t15", weight: "semibold")
            VStack(spacing: skin.size.s4) {
                ForEach(work) { issue in
                    HStack(spacing: skin.size.s8) {
                        Text(issue.key).citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.palette.accentSecondary))
                        Text(issue.title).citadelFont("t12").lineLimit(1)
                        Spacer()
                        if let points = issue.points {
                            Text("\(points) pts").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                        }
                    }
                    .padding(.horizontal, skin.size.s10).frame(height: skin.size.s34)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o05)),
                        in: RoundedRectangle(cornerRadius: skin.size.s8))
                }
            }
            AinkradFormRow(title: "Move to") {
                if peers.isEmpty {
                    Text("No other \(agent.role)").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                } else {
                    AinkradSegmentedPicker(items: peers.map(\.id), selection: $target) { id in
                        model.agents[id]?.name ?? ""
                    }
                    .fixedSize()
                }
            }
            HStack(spacing: skin.size.s8) {
                Text("Live runs finish first; queued issues move now.").citadelFont("t11").foregroundStyle(
                    skin.color(skin.text.faint))
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { model.orgPage.sheet = nil }.borderless().fixedSize()
                AinkradButton(title: "Reassign \(work.count)") {
                    if let to = model.agents[target] { store.reassign(work, to: to) }
                    model.orgPage.sheet = nil
                }
                .fixedSize().disabled(model.agents[target] == nil)
            }
        }
        .onAppear { target = peers.first?.id ?? 0 }
    }
}

/// Terminate (prototype confirm with an optional reason), `POST /agents/{id}/terminate` (API minor 17); an older
/// server keeps it off.
struct TerminateSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @State private var reason = ""
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Terminate \(agent.name)?").citadelFont("t15", weight: "semibold")
            Text(
                "Its runs stop, its issues return to the team queue, and its history stays readable. Re-hiring starts a fresh agent."
            )
            .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted)).fixedSize(
                horizontal: false, vertical: true)
            AinkradTextArea(text: $reason, placeholder: "Reason for the audit log (optional)", minHeight: skin.size.s60)
            if !store.serverSupports(minor: CitadelStore.structureMinor) {
                NeedsServer(text: CitadelStore.needsServerUpdate)
            }
            SheetButtons(
                confirm: "Terminate", destructive: true,
                enabled: store.serverSupports(minor: CitadelStore.structureMinor)
            ) {
                store.terminate(agent, reason: reason)
                return true
            } cancel: {
                model.orgPage.sheet = nil
            }
        }
    }
}

/// A faint "needs server" line under a control the API cannot back yet.
struct NeedsServer: View {
    let text: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: skin.size.s6) {
            Image(systemName: "server.rack")
            Text(text).fixedSize(horizontal: false, vertical: true)
        }
        .citadelFont("t11").foregroundStyle(skin.color(skin.palette.warning).opacity(skin.opacity.o85))
    }
}

/// Cancel · confirm at a sheet's foot; `confirm` returns whether the sheet should close.
struct SheetButtons: View {
    let confirm: String
    var destructive = false
    var enabled = true
    let action: () -> Bool
    let cancel: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s8) {
            Spacer()
            AinkradButton(title: "Cancel", style: .ghost, action: cancel).borderless().fixedSize()
            AinkradButton(title: confirm, style: destructive ? .danger : .primary) {
                if action() { cancel() }
            }
            .fixedSize().disabled(!enabled)
        }
    }
}

/// `8M`, `500k`, `8000000` → tokens.
enum TokenAmount {
    static func parse(_ text: String) -> Int64? {
        let t = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: "")
        let unit: Double = t.hasSuffix("m") ? 1_000_000 : t.hasSuffix("k") ? 1_000 : 1
        let number = Double(unit == 1 ? t : String(t.dropLast()))
        return number.map { Int64(($0 * unit).rounded()) }
    }
}
