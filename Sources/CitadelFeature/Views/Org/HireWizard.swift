import AinkradAppKit
import SwiftUI

/// What the hire wizard has picked so far (prototype `hire.js` H).
struct HireDraft: Equatable {
    var role = HireCatalog.roles[0]
    var name = ""
    var team: Int64?
    var description = ""
    var reportsTo: Int64?
    var tags: Set<String> = ["linux"]
    var sandbox = "workspace-write"
    var effort = "medium"
    var instructions = HireCatalog.roles[0].instructions
    var guidelines = HireCatalog.guidelines.prefix(5).map(\.text)
    var allGuidelines = HireCatalog.guidelines.map(\.text)
    var skills: Set<String> = []
    var harness = HireCatalog.roles[0].harness
    var model = HireCatalog.roles[0].model
    var budget = Fmt.tokens(HireCatalog.roles[0].budget)
    var warn = "80"
    var cap = "200k"
    var palette = AinkradFigurePalette.all[0].id

    /// A role fills in sensible defaults for every later step.
    mutating func pick(_ role: HireCatalog.Role) {
        self.role = role
        harness = role.harness
        model = role.model
        budget = Fmt.tokens(role.budget)
        instructions = role.instructions
    }
}

/// "＋ New agent" (prototype `hire.js`, 980): Role & team → Details → Instructions → Model & budget → Look, with a
/// live preview of the agent's figure. Propose hire sends a hire approval; nothing runs until it is approved.
struct HireWizard: View {
    let store: CitadelStore
    let model: CompanyModel
    var team: Int64?
    var step: Int = 0
    var close: (() -> Void)?
    @State private var draft = HireDraft()
    @State private var current = 0
    @State private var flash = false
    @Environment(\.ainkradSkin) private var skin

    static let steps = ["Role & team", "Details", "Instructions", "Model", "Look"]

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: skin.size.s14) {
                Text("New agent").citadelFont("t16", weight: "semibold")
                AinkradStepBar(steps: Self.steps, current: $current)
                ScrollView {
                    HireStepPane(
                        model: model, draft: $draft, step: current, leads: leads,
                        extended: store.serverSupports(minor: CitadelStore.structureMinor)
                    )
                    .padding(.top, skin.size.s4)
                    .padding(.bottom, skin.size.s24)
                }
                .scrollIndicators(.never)
            }
            .padding(.top, skin.size.s22)
            .padding(.horizontal, skin.size.s24)
            .frame(maxWidth: .infinity)
            side
                .frame(width: skin.size.s300)
                .background(skin.color(.palette("black", skin.opacity.o18)))
        }
        .frame(height: skin.size.s640)
        .padding(.horizontal, -skin.size.s24)
        .padding(.vertical, -skin.size.s22)
        .onAppear {
            current = step
            draft.team = team ?? model.departments.first?.teams.first?.id
            draft.name = HireCatalog.names[model.agents.count % HireCatalog.names.count]
            draft.palette = AinkradFigurePalette.all[(model.agents.count * 5) % AinkradFigurePalette.all.count].id
            if store.model?.orgPage.pool.isEmpty == true { store.loadOrgExtras() }
        }
        .onChange(of: draft) { old, new in
            guard old.name == new.name, old.description == new.description, old.instructions == new.instructions
            else { return }
            flash = true
            Task {
                try? await Task.sleep(for: .milliseconds(700))
                flash = false
            }
        }
        .onChange(of: draft.team) { _, _ in draft.reportsTo = nil }
    }

    /// Who it can report to: the team lead, the team's POs, the department head, the CEO.
    private var leads: [AgentInfo] {
        guard let id = draft.team,
            let (department, team) = model.departments.lazy.compactMap({ d in
                d.teams.first { $0.id == id }.map { (d, $0) }
            }).first
        else { return model.ceo.map { [$0] } ?? [] }
        let pos = team.seats.filter { $0.teamRole == "product_owner" }.compactMap { model.agents[$0.agentID] }
        var seen = Set<Int64>()
        return ([model.lead(of: team)] + pos + [model.head(of: department), model.ceo]).compactMap { $0 }
            .filter { seen.insert($0.id).inserted }.prefix(4).map { $0 }
    }

    private var teamName: String {
        model.departments.flatMap(\.teams).first { $0.id == draft.team }?.name ?? "no team"
    }

    private var side: some View {
        let reports = model.agent(draft.reportsTo) ?? leads.first
        let palette = AinkradFigurePalette.named(draft.palette) ?? .neonTide
        return VStack(spacing: skin.size.s14) {
            VStack(spacing: skin.size.s4) {
                AinkradAgentFigure(
                    name: draft.name, state: flash ? .success : .idle, palette: palette,
                    harness: AgentLook.harness(draft.harness), size: skin.size.s104, isActive: true
                )
                .padding(.bottom, skin.size.s8)
                Text(draft.name.isEmpty ? "Unnamed" : draft.name).citadelFont("t17", weight: "semibold")
                (Text(draft.role.name.uppercased()).font(
                    skin.font(AinkradFontToken(sizeKey: "t9_5", weight: "semibold"))
                )
                .foregroundStyle(skin.color(skin.text.faint)) + Text(" · \(teamName)"))
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                Grid(alignment: .leading, horizontalSpacing: skin.size.s12, verticalSpacing: skin.size.s6) {
                    row("Harness", "\(AgentLook.harnessName(draft.harness)) · \(HireCatalog.modelName(draft.model))")
                    row("Budget", "\(draft.budget) tok / mo · warn \(draft.warn)%")
                    row("Fallback", "\(AgentLook.harnessName(draft.harness)) first")
                    row("Reports to", reports?.name ?? "—")
                    row("Sandbox", draft.sandbox)
                    row("Guidelines", "\(draft.guidelines.count) on")
                }
                .padding(.top, skin.size.s12)
                if !draft.skills.isEmpty {
                    AinkradFlowLayout(spacing: skin.size.s4, lineSpacing: skin.size.s4) {
                        ForEach(draft.skills.sorted(), id: \.self) { skill in
                            Text(skill).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.muted))
                                .padding(.horizontal, skin.size.s8).frame(height: skin.size.s22)
                                .overlay(
                                    RoundedRectangle(cornerRadius: skin.size.s6).strokeBorder(
                                        skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
                        }
                    }
                    .padding(.top, skin.size.s8)
                }
            }
            .padding(.vertical, skin.size.s18)
            .padding(.horizontal, skin.size.s14)
            .frame(maxWidth: .infinity)
            .background(
                skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s14)
            )
            .overlay(
                RoundedRectangle(cornerRadius: skin.size.s14).strokeBorder(
                    skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
            (Text("Joins as a ") + Text("pending hire").bold()
                + Text(" — it lands in Approvals and nothing runs until you approve."))
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).frame(
                    maxWidth: .infinity, alignment: .leading)
            Spacer(minLength: 0)
            HStack(spacing: skin.size.s8) {
                AinkradButton(title: current == 0 ? "Cancel" : "Back", style: .ghost) {
                    if current == 0 { dismiss() } else { current -= 1 }
                }
                .borderless().frame(minWidth: skin.size.s96).fixedSize()
                Spacer()
                AinkradButton(title: current == Self.steps.count - 1 ? "Propose hire" : "Next") {
                    if current < Self.steps.count - 1 { current += 1 } else { propose() }
                }
                .frame(minWidth: skin.size.s96).fixedSize()
                .disabled(draft.name.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
        .padding(skin.size.s22)
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(skin.color(skin.text.faint))
            Text(value).fontWeight(.medium).lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .citadelFont("t11")
    }

    private func dismiss() {
        if let close { close() } else { model.orgPage.sheet = nil }
    }

    /// The proposal carries name, role, harness, model, reports-to and runner tags. From API minor 17 it also seats
    /// the hire and carries description, effort, sandbox, instructions, guidelines and palette; an older server
    /// gets the team in the justification instead.
    private func propose() {
        var proposal = AgentDraft()
        proposal.name = draft.name.trimmingCharacters(in: .whitespaces)
        proposal.role = draft.role.name
        proposal.harness = draft.harness
        proposal.model = draft.model
        proposal.reportsTo = draft.reportsTo ?? leads.first?.id
        proposal.runnerTags = draft.tags.sorted().joined(separator: " ")
        let why = draft.description.trimmingCharacters(in: .whitespacesAndNewlines)
        if store.serverSupports(minor: CitadelStore.structureMinor) {
            proposal.justification = why.isEmpty ? draft.role.purpose : why
            proposal.description = why
            proposal.effort = draft.effort
            proposal.sandbox = draft.sandbox
            proposal.instructions = draft.instructions
            proposal.guidelines = draft.guidelines
            proposal.teamID = draft.team
            proposal.paletteID = draft.palette
        } else {
            proposal.justification = "\(why.isEmpty ? draft.role.purpose : why) · for \(teamName)"
        }
        store.proposeHire(proposal, palette: draft.palette) { dismiss() }
    }
}

/// The wizard's entry from the empty-company onboarding (11 A) and the sweep's form shot.
struct ProposeAgentSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    @Binding var isPresented: Bool

    var body: some View {
        HireWizard(store: store, model: model) { isPresented = false }
    }
}
