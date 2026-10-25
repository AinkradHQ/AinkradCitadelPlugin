import AinkradAppKit
import SwiftUI

/// One step of the hire wizard (prototype `hire.js` panes).
struct HireStepPane: View {
    let model: CompanyModel
    @Binding var draft: HireDraft
    let step: Int
    let leads: [AgentInfo]
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s16) {
            switch step {
            case 0: roleAndTeam
            case 1: details
            case 2: instructions
            case 3: modelAndBudget
            default: look
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func head(_ title: String, _ line: String) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s3) {
            Text(title).citadelFont("t15", weight: "semibold")
            Text(line).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
        }
    }

    // MARK: - 0 Role & team

    @ViewBuilder private var roleAndTeam: some View {
        head(
            "Role & team",
            "What the agent does and where it works. A role fills in sensible defaults for every later step.")
        field("Role") {
            CardGrid(columns: 3) {
                ForEach(HireCatalog.roles) { role in
                    let on = role == draft.role
                    ChoiceCard(isOn: on, height: skin.size.s52, action: { draft.pick(role) }) {
                        CardGlyph(glyph: role.symbol, isOn: on)
                        CardText(title: role.name, caption: role.purpose)
                    }
                    .help(role.purpose)
                }
                ChoiceCard(isAdd: true, height: skin.size.s52, action: { model.orgPage.stack(.role(nil)) }) {
                    CardGlyph(glyph: "plus")
                    CardText(title: "Custom role", caption: "Name it and set defaults")
                }
            }
        }
        field("Team") {
            CardGrid(columns: 4) {
                ForEach(teamPairs, id: \.team.id) { pair in
                    let team = pair.team
                    let department = pair.department
                    ChoiceCard(
                        isOn: draft.team == team.id, height: skin.size.s70, axis: .vertical,
                        action: { draft.team = team.id }
                    ) {
                        HStack(spacing: skin.size.s8) {
                            if let project = model.project(of: team) { KeyChip(key: project.key) }
                            Text(team.name).citadelFont("t13", weight: "semibold").lineLimit(1)
                        }
                        Text("\(department.name) · \(Wording.count(team.seats.count, "agent"))").citadelFont("t11")
                            .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                        Spacer(minLength: 0)
                        Faces(model: model, ids: team.seats.prefix(6).map(\.agentID), size: skin.size.s20)
                    }
                }
                ChoiceCard(
                    isAdd: true, height: skin.size.s70, axis: .vertical,
                    action: { model.orgPage.stack(.team(nil)) }
                ) {
                    HStack(spacing: skin.size.s8) {
                        KeyChip(key: "＋")
                        Text("New team").citadelFont("t13", weight: "semibold")
                    }
                    Text("Department and project").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    Spacer(minLength: 0)
                }
            }
        }
        NeedsServer(
            text:
                "A proposal can't carry a seat yet (AgentProposal has no team) — the team is written into its justification."
        )
    }

    private var teamPairs: [(department: DepartmentInfo, team: TeamInfo)] {
        var out: [(department: DepartmentInfo, team: TeamInfo)] = []
        for d in model.departments { for t in d.teams { out.append((d, t)) } }
        return out
    }

    // MARK: - 1 Details

    @ViewBuilder private var details: some View {
        head("Details", "Who it is, who it answers to, and how much it may touch.")
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                AinkradTextField(text: $draft.name, placeholder: "Name").citadelFont("t20", weight: "semibold")
                Dice(roll: rollName)
            }
            .padding(.horizontal, skin.size.s8).padding(.top, skin.size.s6)
            AinkradTextArea(
                text: $draft.description,
                placeholder:
                    "What this agent is for — one or two lines, shown on its profile and to the agents it works with",
                minHeight: skin.size.s50)
        }
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s12).strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
        field("Reports to") {
            CardGrid(columns: 4) {
                ForEach(leads) { agent in
                    PersonCard(
                        model: model, agent: agent, line: relation(agent),
                        isOn: (draft.reportsTo ?? leads.first?.id) == agent.id
                    ) { draft.reportsTo = agent.id }
                }
            }
        }
        field("Sandbox") { SandboxCards(selection: $draft.sandbox) }
        field("Runs on runners tagged") { RunnerTagCards(model: model, selection: $draft.tags) }
    }

    private func rollName() {
        let names = HireCatalog.names
        draft.name = names[((names.firstIndex(of: draft.name) ?? -1) + 1) % names.count]
    }

    private func relation(_ agent: AgentInfo) -> String {
        if agent.orgRole == "ceo" { return "CEO" }
        if model.headedDepartment(of: agent.id) != nil { return "dept head" }
        if let team = model.departments.flatMap(\.teams).first(where: { $0.id == draft.team }),
            model.lead(of: team)?.id == agent.id
        {
            return "team lead"
        }
        return "team \(agent.role.lowercased())"
    }

    // MARK: - 2 Instructions

    @ViewBuilder private var instructions: some View {
        head("Instructions", "What the agent is told on every run, the rules it must keep, and the skills it can load.")
        InstructionsEditor(
            title: "System instructions", pill: "\(draft.role.name) template", text: $draft.instructions,
            template: draft.role.instructions)
        field("Guidelines · \(draft.guidelines.count) on") {
            GuidelineCards(on: $draft.guidelines, all: $draft.allGuidelines)
        }
        let library = Dictionary(grouping: model.orgPage.skillLibrary, by: \.name).compactMap {
            $0.value.max { $0.version < $1.version }
        }.sorted { $0.name < $1.name }
        field("Skills · \(draft.skills.count) loaded") {
            if library.isEmpty {
                Text("The company has no skills yet — publish them in Company settings.").citadelFont("t12")
                    .foregroundStyle(skin.color(skin.text.faint))
            }
            CardGrid(columns: 2) {
                ForEach(library) { skill in
                    let on = draft.skills.contains(skill.name)
                    ChoiceCard(isOn: on, height: skin.size.s50, action: { toggle(skill.name) }) {
                        CheckBox(isOn: on)
                        CardText(
                            title: "\(skill.name) v\(skill.version)",
                            caption: "≈ \(Fmt.tokens(skill.bytes / 4)) tokens", mono: true)
                    }
                }
            }
        }
        NeedsServer(
            text:
                "Instructions, guidelines, skills, sandbox and effort aren't stored on an agent yet — the server needs fields for them."
        )
    }

    private func toggle(_ skill: String) {
        if draft.skills.contains(skill) { draft.skills.remove(skill) } else { draft.skills.insert(skill) }
    }

    // MARK: - 3 Model & budget

    @ViewBuilder private var modelAndBudget: some View {
        head("Model & budget", "Which harness runs it, how hard it thinks, and what it may spend.")
        field("Harness") { HarnessCards(model: model, selection: $draft.harness) }
        field("Model") { ModelCards(harness: draft.harness, selection: $draft.model) }
        field("Effort") { EffortCards(selection: $draft.effort) }
        field("Fallback chain") {
            Text(
                "Its own model first, then the company's default chain — pick another in Accounts once it is hired."
            )
            .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
        }
        VStack(alignment: .leading, spacing: skin.size.s8) {
            HStack {
                GroupLabel(title: "Budget")
                AinkradSegmentedPicker(
                    items: HireCatalog.budgetPresets,
                    selection: Binding(
                        get: { TokenAmount.parse(draft.budget) ?? 0 }, set: { draft.budget = Fmt.tokens($0) })
                ) { Fmt.tokens($0) }
                .fixedSize()
            }
            BudgetFields(
                budget: $draft.budget, warn: $draft.warn, cap: $draft.cap,
                footnote:
                    "A run past \(draft.cap) tokens stops and escalates to \((model.agent(draft.reportsTo) ?? leads.first)?.name ?? "its lead"). The budget is set once the hire is approved."
            )
        }
        .onChange(of: draft.harness) { _, harness in
            if HireCatalog.models[harness]?.contains(where: { $0.wire == draft.model }) != true {
                draft.model = HireCatalog.models[harness]?.first?.wire ?? ""
            }
        }
    }

    // MARK: - 4 Look

    @ViewBuilder private var look: some View {
        let palette = AinkradFigurePalette.named(draft.palette) ?? .neonTide
        head("Look", "Its colour everywhere it appears. The figure animates by state, so you can read it at a glance.")
        field("Colour · \(palette.name)") { PaletteGrid(selection: $draft.palette) }
        field("In every state") {
            CardGrid(columns: 4, spacing: skin.size.s10) {
                ForEach(
                    [
                        (AinkradFigureState.idle, "Idle"), (.working, "Working"), (.confused, "Needs you"),
                        (.sleepy, "Asleep"),
                    ],
                    id: \.1
                ) { state, label in
                    VStack(spacing: skin.size.s8) {
                        AinkradAgentFigure(
                            name: draft.name, state: state, palette: palette, harness: AgentLook.harness(draft.harness),
                            size: skin.size.s64, isActive: true)
                        Text(label).citadelFont("t12", weight: "medium").foregroundStyle(skin.color(skin.text.muted))
                    }
                    .padding(.top, skin.size.s14).padding(.bottom, skin.size.s12)
                    .frame(maxWidth: .infinity)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o05)),
                        in: RoundedRectangle(cornerRadius: skin.size.s10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: skin.size.s10).strokeBorder(
                            skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
                }
            }
        }
    }
}

/// ⟳ that turns a quarter on hover: the next suggested name.
private struct Dice: View {
    let roll: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(help: "Suggest another name", action: roll) {
            Text("⟳").citadelFont("t15").foregroundStyle(
                hovering ? skin.color(skin.text.primary) : skin.color(skin.text.muted)
            )
            .frame(width: skin.size.s30, height: skin.size.s30)
            .background(
                skin.color(.palette("foreground", hovering ? skin.opacity.o08 : 0)),
                in: RoundedRectangle(cornerRadius: skin.size.s8)
            )
            .rotationEffect(.degrees(hovering ? 90 : 0))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}
