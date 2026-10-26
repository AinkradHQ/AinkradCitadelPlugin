import AinkradAppKit
import SwiftUI

/// Org → Structure (prototype `structure.js` orgStructure, 920): Departments · Teams · Roles as tabs of card
/// grids; a card opens its form stacked on top, the dashed card a new one.
struct StructureSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    /// The company's roles from API minor 18 (its starter list until it has one of its own), else the built-ins.
    private var supported: Bool { store.serverSupports(minor: CitadelStore.structureMinor) }

    private var roles: [HireCatalog.Role] {
        store.rolesOn && !model.roles.isEmpty ? model.roles.map(\.catalogRole) : HireCatalog.roles
    }

    var body: some View {
        let page = model.orgPage
        let teams = model.departments.flatMap(\.teams)
        AinkradSheetFrame(
            tile: "point.3.connected.trianglepath.dotted", symbol: true, title: "Structure",
            line:
                "Departments have a head manager, teams have a lead, and roles are the templates new agents start from."
        ) {
            AinkradGlideTabs(
                [
                    AinkradGlideTab(
                        OrgPage.StructureTab.departments, title: "Departments", systemImage: "building.2",
                        count: "\(model.departments.count)"),
                    AinkradGlideTab(.teams, title: "Teams", systemImage: "person.2", count: "\(teams.count)"),
                    AinkradGlideTab(
                        .roles, title: "Roles", systemImage: "person", count: "\(roles.count)"),
                ], selection: Binding(get: { page.structureTab }, set: { page.structureTab = $0 }))
            AinkradCardGrid(columns: 3, spacing: skin.size.s10) {
                switch page.structureTab {
                case .departments:
                    ForEach(model.departments) { department(model, $0) }
                    addCard("New department", "Name and head manager") { page.stack(.department(nil)) }
                case .teams:
                    ForEach(teams) { team(model, $0) }
                    addCard("New team", "Department, lead, project") { page.stack(.team(nil)) }
                case .roles:
                    ForEach(roles) { role($0) }
                    addCard("New role", "Icon, defaults, instructions") { page.stack(.role(nil)) }
                }
            }
        } foot: {
            Text("Chain of command: agent → team lead → department head → CEO.").citadelFont("t11")
                .foregroundStyle(skin.color(skin.text.faint))
            Spacer()
            AinkradButton(title: "Done") { page.sheet = nil }.frame(minWidth: skin.size.s96).fixedSize()
        }
        .task { store.loadRoles() }
    }

    private func card<Top: View, Foot: View>(
        title: String, line: String, open: @escaping () -> Void, remove: (() -> Void)? = nil,
        @ViewBuilder top: () -> Top, @ViewBuilder foot: () -> Foot
    ) -> some View {
        AinkradChoiceCard(height: skin.size.s108, axis: .vertical, action: open) {
            HStack { top() }.frame(height: skin.size.s28)
            Text(title).citadelFont("t13", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                .padding(.top, skin.size.s8)
            Text(line).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            Spacer(minLength: 0)
            HStack(spacing: skin.size.s6) { foot() }.frame(height: skin.size.s20)
        }
        .modifier(HoverRemove(remove: remove, name: title))
    }

    private func department(_ model: CompanyModel, _ department: DepartmentInfo) -> some View {
        let head = model.head(of: department)
        return card(
            title: department.name,
            line:
                "\(Wording.count(department.teams.count, "team")) · \(Wording.count(department.agentIDs.count + (head == nil ? 0 : 1), "agent"))",
            open: { model.orgPage.stack(.department(department.id)) },
            remove: department.teams.isEmpty && department.agentIDs.isEmpty && supported
                ? { store.deleteDepartment(department) {} } : nil
        ) {
            InitialTile(letter: department.name, side: skin.size.s28)
        } foot: {
            if let head {
                AgentFigure(agent: head, model: model, size: skin.size.s20)
                who("head · \(head.name)")
            } else {
                Text("no head — assign one").citadelFont("t11").foregroundStyle(skin.color(skin.palette.warning))
            }
        }
    }

    private func team(_ model: CompanyModel, _ team: TeamInfo) -> some View {
        let lead = model.lead(of: team)
        let department = model.departments.first { $0.teams.contains { $0.id == team.id } }
        let line = [department?.name, model.cadence(of: team)?.text, Wording.count(team.seats.count, "agent")]
            .compactMap { $0 }.joined(separator: " · ")
        return card(
            title: team.name, line: line, open: { model.orgPage.stack(.team(team.id)) },
            remove: team.seats.isEmpty && supported ? { store.deleteTeam(team) {} } : nil
        ) {
            if let project = model.project(of: team) { KeyChip(key: project.key) }
        } foot: {
            if let lead {
                AgentFigure(agent: lead, model: model, size: skin.size.s20)
                who("★ lead · \(lead.name)")
            } else {
                Text("★ no lead — assign one").citadelFont("t11").foregroundStyle(skin.color(skin.palette.warning))
            }
            Spacer(minLength: 0)
            Faces(model: model, ids: team.seats.map(\.agentID).filter { $0 != lead?.id }.prefix(4).map { $0 })
        }
    }

    private func role(_ role: HireCatalog.Role) -> some View {
        let count = model.agents.values.filter { $0.role.lowercased() == role.name.lowercased() }.count
        let stored = model.roles.first { $0.name.lowercased() == role.name.lowercased() }
        return card(
            title: role.name, line: role.purpose, open: { model.orgPage.stack(.role(role.name)) },
            remove: count == 0 && store.rolesOn ? stored.map { stored in { store.deleteRole(stored) {} } } : nil
        ) {
            AinkradChoiceGlyph(role.symbol)
        } foot: {
            HarnessTag(harness: role.harness, size: skin.size.s20)
            who("\(HireCatalog.modelName(role.model)) · \(Fmt.tokens(role.budget)) tok")
            Spacer(minLength: 0)
            Text(Wording.count(count, "agent")).citadelFont("t10_5", mono: true).foregroundStyle(
                skin.color(skin.text.faint))
        }
    }

    private func who(_ text: String) -> some View {
        Text(text).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
    }

    private func addCard(_ title: String, _ line: String, open: @escaping () -> Void) -> some View {
        AinkradChoiceCard(isAdd: true, height: skin.size.s108, axis: .vertical, action: open) {
            VStack(spacing: skin.size.s4) {
                Text("＋").citadelFont("t13").foregroundStyle(skin.color(skin.text.muted))
                    .frame(width: skin.size.s28, height: skin.size.s28)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o06)),
                        in: RoundedRectangle(cornerRadius: skin.size.s8))
                Text(title).citadelFont("t13", weight: "semibold").padding(.top, skin.size.s2)
                Text(line).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Overlapping faces (`.h-faces`): small figures, each pulled under the previous one.
struct Faces: View {
    let model: CompanyModel
    let ids: [Int64]
    var size: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let side = size ?? skin.size.s18
        HStack(spacing: -side * 0.28) {
            ForEach(ids, id: \.self) { id in
                if let agent = model.agents[id] { AgentFigure(agent: agent, model: model, size: side) }
            }
        }
    }
}

/// A hover ✕ at a card's corner, only for an item nothing uses (no teams or agents, no seats, no agents in the role).
private struct HoverRemove: ViewModifier {
    let remove: (() -> Void)?
    let name: String
    @State private var hovering = false
    @State private var confirms = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .overlay(alignment: .topTrailing) {
                if let remove, hovering {
                    AinkradIconButton(
                        systemName: "xmark", size: skin.size.s22, tooltip: "Delete \(name)", action: { confirms = true }
                    )
                    .padding(skin.size.s6)
                    .transition(.opacity)
                }
            }
            .citadelHover($hovering)
            .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: hovering)
            .ainkradConfirmDialog(
                isPresented: $confirms, title: "Delete \(name)?", message: "Nothing uses it. This cannot be undone.",
                confirmTitle: "Delete", isDestructive: true
            ) { remove?() }
    }
}
