import AinkradAppKit
import SwiftUI

// The Structure forms (prototype `structure.js` teamSheet / deptSheet / roleSheet). Departments, teams and seats
// save with the API minor 17 endpoints; on an older server Save stays off with a "needs a server update" line.
// Roles have no server resource yet, so the role form stays a drawn, read-only template.

/// A person card (`personCard`): figure 30, name, what they do.
struct PersonCard: View {
    let model: CompanyModel
    let agent: AgentInfo
    let line: String
    let isOn: Bool
    let pick: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradChoiceCard(isOn: isOn, height: skin.size.s54, action: pick) {
            AgentFigure(agent: agent, model: model, size: skin.size.s30)
            AinkradChoiceText(title: agent.name, caption: line)
        }
    }
}

struct TeamSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    let team: Int64?
    @State private var name = ""
    @State private var department: Int64 = 0
    @State private var lead: Int64?
    @State private var key = ""
    @State private var sprint = false
    @Environment(\.ainkradSkin) private var skin

    private var supported: Bool { store.serverSupports(minor: CitadelStore.structureMinor) }

    var body: some View {
        let current = model.departments.flatMap(\.teams).first { $0.id == team }
        let shown = (key.isEmpty ? String(name.prefix(3)) : key).uppercased()
        AinkradSheetFrame(
            tile: shown.isEmpty ? "NEW" : shown, title: current == nil ? "New team" : "Edit team",
            line: "A team sits in a department, works one project, and has one lead."
        ) {
            field("Name") { AinkradTextField(text: $name, placeholder: "Payments") }
            field("Department") {
                AinkradCardGrid(columns: 2) {
                    ForEach(model.departments) { item in
                        let head = model.head(of: item)
                        AinkradChoiceCard(
                            isOn: item.id == department, height: skin.size.s56, action: { department = item.id }
                        ) {
                            InitialTile(letter: item.name, side: skin.size.s32)
                            AinkradChoiceText(
                                title: item.name, caption: head.map { "head \($0.name) · \($0.role)" } ?? "no head yet")
                        }
                    }
                }
            }
            field("Team lead · the team reports to them") {
                let pool = leadPool(current)
                if pool.isEmpty {
                    Text("No agents in this department yet — hire one, then make them lead.").citadelFont("t12")
                        .foregroundStyle(skin.color(skin.text.faint))
                } else {
                    AinkradCardGrid(columns: 4) {
                        ForEach(pool) { agent in
                            PersonCard(model: model, agent: agent, line: agent.role, isOn: agent.id == lead) {
                                lead = agent.id
                            }
                        }
                    }
                }
                if current == nil {
                    Text("The lead moves into the new team from their current one.").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                }
            }
            field("Project key") {
                HStack(spacing: skin.size.s12) {
                    AinkradTextField(text: $key, placeholder: "PAY").monospaced().frame(width: skin.size.s110)
                    (Text("Issues read ")
                        + Text("\(shown.isEmpty ? "PAY" : shown)-1").foregroundStyle(
                            skin.color(skin.palette.accentSecondary)) + Text(", ")
                        + Text("\(shown.isEmpty ? "PAY" : shown)-2").foregroundStyle(
                            skin.color(skin.palette.accentSecondary)) + Text(" …"))
                        .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                }
            }
            field("Cadence") {
                AinkradCardGrid(columns: 2) {
                    cadence("Sprint", "Time-boxed sprints the PO plans with the lead", "clock", on: sprint) {
                        sprint = true
                    }
                    cadence("Kanban", "A continuous flow — pick up the next issue", "line.3.horizontal", on: !sprint) {
                        sprint = false
                    }
                }
            }
            if let current, !current.seats.isEmpty {
                field("Members") {
                    ForEach(current.seats, id: \.agentID) { seat in
                        if let agent = model.agents[seat.agentID] {
                            HStack(spacing: skin.size.s8) {
                                AgentFigure(agent: agent, model: model, size: skin.size.s22)
                                Text(agent.name).citadelFont("t12", weight: "medium")
                                Text(seat.teamRole.replacingOccurrences(of: "_", with: " ")).citadelFont("t11")
                                    .foregroundStyle(skin.color(skin.text.faint))
                                Spacer()
                                AinkradButton(title: "Remove", style: .ghost) { store.unseat(agent, from: current) }
                                    .compact().borderless().fixedSize().disabled(!supported)
                                    .help(store.help(ready: "Take \(agent.name) off the team"))
                            }
                        }
                    }
                }
            }
            Text("The project key and cadence belong to the team's project; they are not sent from here.")
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            if !supported { NeedsServer(text: CitadelStore.needsServerUpdate) }
        } foot: {
            if let current {
                AinkradButton(title: "Delete team", style: .danger) {
                    store.deleteTeam(current) { model.orgPage.close() }
                }
                .fixedSize().disabled(!supported).help(store.help(ready: "Deletes the team with its seats"))
            }
            Spacer()
            AinkradButton(title: "Cancel", style: .ghost) { model.orgPage.close() }.borderless().fixedSize()
            AinkradButton(title: current == nil ? "Create team" : "Save team") {
                store.saveTeam(current, name: name, department: department, lead: lead) { model.orgPage.close() }
            }
            .fixedSize().disabled(!supported || name.trimmingCharacters(in: .whitespaces).isEmpty)
            .help(store.help())
        }
        .onAppear {
            guard let current else {
                department = model.departments.first?.id ?? 0
                return
            }
            name = current.name
            department = model.departments.first { $0.teams.contains { $0.id == current.id } }?.id ?? 0
            lead = model.lead(of: current)?.id
            key = model.project(of: current)?.key ?? ""
            sprint = model.cadence(of: current)?.isSprint ?? false
        }
    }

    /// The team's members; for a new team, the department's seated agents.
    private func leadPool(_ current: TeamInfo?) -> [AgentInfo] {
        let ids =
            current.map { $0.seats.map(\.agentID) }
            ?? model.departments.first { $0.id == department }?.agentIDs ?? []
        return ids.compactMap { model.agents[$0] }.filter { !$0.isHirePending }.prefix(8).map { $0 }
    }

    private func cadence(_ title: String, _ blurb: String, _ symbol: String, on: Bool, pick: @escaping () -> Void)
        -> some View
    {
        AinkradChoiceCard(isOn: on, height: skin.size.s64, action: pick) {
            AinkradChoiceGlyph(symbol, isOn: on)
            AinkradChoiceText(title: title, caption: blurb, wraps: true)
        }
    }
}

struct DepartmentSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    let department: Int64?
    @State private var name = ""
    @State private var head: Int64?
    @State private var about = ""
    @Environment(\.ainkradSkin) private var skin

    private var supported: Bool { store.serverSupports(minor: CitadelStore.structureMinor) }

    var body: some View {
        let current = model.departments.first { $0.id == department }
        AinkradSheetFrame(
            tile: String((name.isEmpty ? "D" : name).prefix(1)).uppercased(),
            title: current.map { "Edit \($0.name)" } ?? "New department",
            line: "A department groups teams under one head manager, who reports to the CEO."
        ) {
            field("Name") { AinkradTextField(text: $name, placeholder: "Sales") }
            field("Head manager") {
                AinkradCardGrid(columns: 4) {
                    ForEach(pool(current)) { agent in
                        PersonCard(model: model, agent: agent, line: line(agent), isOn: agent.id == head) {
                            head = agent.id
                        }
                    }
                }
                Text(
                    "Team leads in this department report to the head. Picking someone from another department moves them here."
                )
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            field("What it owns") {
                AinkradTextArea(
                    text: $about, placeholder: "One line — shown on the org chart and to the CEO when it routes work",
                    minHeight: skin.size.s56)
            }
            if !supported { NeedsServer(text: CitadelStore.needsServerUpdate) }
        } foot: {
            if let current, current.teams.isEmpty {
                AinkradButton(title: "Delete department", style: .danger) {
                    store.deleteDepartment(current) { model.orgPage.close() }
                }
                .fixedSize().disabled(!supported).help(store.help())
            }
            Spacer()
            AinkradButton(title: "Cancel", style: .ghost) { model.orgPage.close() }.borderless().fixedSize()
            AinkradButton(title: current == nil ? "Create department" : "Save") {
                store.saveDepartment(department, name: name, about: about, head: head) { model.orgPage.close() }
            }
            .fixedSize().disabled(!supported || name.trimmingCharacters(in: .whitespaces).isEmpty)
            .help(store.help())
        }
        .onAppear {
            name = current?.name ?? ""
            about = current?.about ?? ""
            head = current.flatMap { model.head(of: $0)?.id } ?? pool(current).first?.id
        }
    }

    /// The current head first, then unseated agents, then team leads.
    private func pool(_ current: DepartmentInfo?) -> [AgentInfo] {
        let headID = current.flatMap { model.head(of: $0)?.id }
        let seated = Set(model.departments.flatMap(\.agentIDs))
        return model.agents.values.filter { $0.orgRole != "ceo" && !$0.isHirePending }
            .sorted {
                ($0.id == headID ? 0 : !seated.contains($0.id) ? 1 : 2, $0.id)
                    < ($1.id == headID ? 0 : !seated.contains($1.id) ? 1 : 2, $1.id)
            }
            .prefix(8).map { $0 }
    }

    private func line(_ agent: AgentInfo) -> String {
        if let headed = model.headedDepartment(of: agent.id), headed.id != department { return "heads \(headed.name)" }
        if let (_, team) = model.team(of: agent.id), model.lead(of: team)?.id == agent.id {
            return "leads \(team.name)"
        }
        return agent.role
    }
}

/// Org › Structure › a role (`orgRole`): the template new agents of the role start from. From API minor 18 it is
/// written to the company's roles (a starter role that is not stored yet is created on Save); older servers keep
/// the built-in templates read-only.
struct RoleSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    let role: String?
    @State private var name = ""
    @State private var purpose = ""
    @State private var symbol = "person"
    @State private var harness = "claude"
    @State private var budget: Int64 = 5_000_000
    @State private var instructions = ""
    @Environment(\.ainkradSkin) private var skin

    private static let symbols = [
        "chevron.left.forwardslash.chevron.right", "checkmark.shield", "star", "doc.text", "server.rack", "pencil",
        "paintpalette", "chart.bar", "person",
    ]

    var body: some View {
        let stored = role.flatMap { name in model.roles.first { $0.name.lowercased() == name.lowercased() } }
        let current = stored?.catalogRole ?? role.flatMap(HireCatalog.role)
        AinkradSheetFrame(
            tile: symbol, symbol: true, title: current.map { "Edit \($0.name)" } ?? "New role",
            line: "A role is a template — new agents in it start with these defaults."
        ) {
            HStack(alignment: .top, spacing: skin.size.s8) {
                field("Name") { AinkradTextField(text: $name, placeholder: "Security") }
                field("Purpose") { AinkradTextField(text: $purpose, placeholder: "Audits code and dependencies") }
            }
            field("Icon") {
                AinkradCardGrid(columns: 9) {
                    ForEach(Self.symbols, id: \.self) { item in
                        AinkradChoiceCard(isOn: item == symbol, height: skin.size.s50, action: { symbol = item }) {
                            Image(systemName: item).citadelFont("t15").frame(maxWidth: .infinity)
                                .foregroundStyle(
                                    item == symbol ? skin.color(skin.palette.white) : skin.color(skin.text.muted))
                        }
                    }
                }
            }
            field("Default harness") { HarnessCards(model: model, selection: $harness, showsPool: false) }
            field("Default budget") {
                AinkradSegmentedPicker(
                    items: [2_500_000, 4_000_000, 5_000_000, 8_000_000, 12_000_000, 20_000_000] as [Int64],
                    selection: $budget
                ) {
                    "\(Fmt.tokens($0)) / mo"
                }
                .fixedSize()
            }
            InstructionsEditor(
                title: "Instructions", pill: nil, text: $instructions, template: nil,
                note: "every agent in this role starts with these")
            if !store.rolesOn {
                NeedsServer(
                    text:
                        "Roles are client templates until the server stores them (\(store.help(minor: CitadelStore.trancheBMinor)))."
                )
            }
        } foot: {
            if let stored {
                AinkradButton(title: "Delete", style: .ghost) {
                    store.deleteRole(stored) { model.orgPage.close() }
                }
                .borderless().fixedSize().disabled(!store.rolesOn)
            }
            Spacer()
            AinkradButton(title: "Cancel", style: .ghost) { model.orgPage.close() }.borderless().fixedSize()
            AinkradButton(title: stored == nil ? "Create role" : "Save role") {
                let first = HireCatalog.models[harness]?.first?.wire
                let keep = stored?.model.flatMap {
                    HireCatalog.models[harness]?.map(\.wire).contains($0) == true ? $0 : nil
                }
                store.saveRole(
                    RoleInfo(
                        id: stored?.id ?? 0, name: name, purpose: purpose, icon: symbol, skills: stored?.skills ?? [],
                        instructions: instructions, harness: harness, model: keep ?? first, budgetTokens: budget),
                    isNew: stored == nil
                ) { model.orgPage.close() }
            }
            .disabled(!store.rolesOn || name.trimmingCharacters(in: .whitespaces).isEmpty).fixedSize()
        }
        .onAppear {
            guard let current else { return }
            name = current.name
            purpose = current.purpose
            symbol = current.symbol
            harness = current.harness
            budget = current.budget
            instructions = current.instructions
        }
    }
}

/// A labelled section of a form (`section > .label`).
@MainActor
func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
    FormSection(label: label, content: content())
}

private struct FormSection<Content: View>: View {
    let label: String
    let content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s8) {
            AinkradGroupLabel(title: label)
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
