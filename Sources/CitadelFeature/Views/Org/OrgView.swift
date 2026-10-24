import AinkradAppKit
import AppKit
import SwiftUI

/// What the org filters keep bright; the rest dims so the org keeps its shape.
enum OrgFilter: String, CaseIterable, Hashable {
    case all = "All"
    case working = "Working"
    case waiting = "Waiting"
    case paused = "Paused"

    func matches(_ agent: AgentInfo) -> Bool {
        switch self {
        case .all: true
        case .working: [.working, .thinking, .loading].contains(agent.figure)
        case .waiting: agent.figure == .listening
        case .paused: agent.isPaused || agent.figure == .sleepy
        }
    }
}

/// Screen 03: company → departments → teams → agents, shown by nesting (decision #32), never connector lines.
struct OrgView: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var filter: OrgFilter = .all
    @State private var width: CGFloat = 0
    @State private var proposing = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Org", crumb: crumb) {
                HStack(spacing: skin.size.s8) {
                    AinkradSegmentedPicker(items: OrgFilter.allCases, selection: $filter) { $0.rawValue }.fixedSize()
                        .controlSize(.small)
                    AinkradIconButton(systemName: "plus", size: skin.size.s30, tooltip: "Propose an agent") {
                        proposing = true
                    }
                    .outlineBox()
                }
            }
            ScrollView {
                VStack(spacing: skin.size.s14) {
                    if let ceo = model.ceo {
                        RouterNode(agent: ceo, model: model, line: "Routes new goals to departments · \(ceo.model)") {
                            store.open(.agent(ceo.id))
                        }
                        .opacity(filter.matches(ceo) ? 1 : skin.opacity.o35)
                    }
                    HStack(alignment: .top, spacing: skin.size.s14) {
                        ForEach(model.departments) { department in
                            DepartmentPanel(store: store, model: model, department: department, filter: filter)
                                .frame(width: departmentWidth(department))
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.width
                    } action: {
                        width = $0
                    }
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.bottom, skin.size.s20)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: filter)
            }
            .offlineDimmed()
        }
        .ainkradPanelModal(isPresented: $proposing, contentWidth: skin.size.s440) {
            ProposeAgentSheet(store: store, model: model, isPresented: $proposing)
        }
    }

    /// `18 agents · 7 working · 1 hire pending`.
    private var crumb: Text {
        let working = model.agents.values.filter { OrgFilter.working.matches($0) }.count
        let pending = model.agents.values.filter(\.isHirePending).count
        var text = Text("\(Wording.count(model.agents.count, "agent")) · \(working) working").foregroundStyle(
            skin.color(skin.text.muted))
        if pending > 0 {
            text =
                text + Text(" · ").foregroundStyle(skin.color(skin.text.muted))
                + Text("\(pending) hire\(pending == 1 ? "" : "s") pending").foregroundStyle(status.warning)
        }
        return text
    }

    /// Departments share the row by how many agent columns they hold: a big team lays its agents out in two.
    private func departmentWidth(_ department: DepartmentInfo) -> CGFloat {
        func weight(_ d: DepartmentInfo) -> CGFloat { (d.agentIDs.count > 6 ? 2 : 1) + 0.5 }
        let total = model.departments.map(weight).reduce(0, +)
        let gaps = skin.size.s14 * CGFloat(max(0, model.departments.count - 1))
        return total > 0 ? max(0, (width - gaps) * weight(department) / total) : 0
    }
}

/// The CEO above everything, the CTO in its department's head: routers say what they do.
struct RouterNode: View {
    let agent: AgentInfo
    let model: CompanyModel
    let line: String
    let open: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradCard(onTap: open) {
            HStack(spacing: skin.size.s10) {
                AgentFigure(agent: agent, model: model, size: skin.size.s32)
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    HStack(alignment: .firstTextBaseline, spacing: skin.size.s4) {
                        Text(agent.name).citadelFont("t13", weight: "semibold")
                            .foregroundStyle(skin.color(skin.text.primary))
                        Text(agent.orgRole.uppercased()).citadelFont("t9_5", weight: "semibold")
                            .foregroundStyle(skin.color(skin.text.faint))
                    }
                    Text(line).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
                }
            }
        }
        .rimTint(.accentViolet)
        .fixedSize()
        .ainkradContextMenu(OrgMenu.items(agent))
    }
}

private struct DepartmentPanel: View {
    let store: CitadelStore
    let model: CompanyModel
    let department: DepartmentInfo
    let filter: OrgFilter
    @Environment(\.ainkradSkin) private var skin

    /// The CTO heads the department its reports work in.
    private var head: AgentInfo? {
        model.agents.values.first { candidate in
            candidate.orgRole == "cto"
                && department.agentIDs.contains { model.agents[$0]?.reportsTo == candidate.id }
        }
    }

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s12) {
                HStack(spacing: skin.size.s10) {
                    Text(department.name).citadelFont("t14", weight: "bold").foregroundStyle(
                        skin.color(skin.text.primary))
                    AinkradBadge(
                        text:
                            "\(department.teams.count) team\(department.teams.count == 1 ? "" : "s") · \(department.agentIDs.count) agents"
                    )
                    Spacer(minLength: skin.size.s8)
                    if let head {
                        RouterNode(agent: head, model: model, line: head.model) { store.open(.agent(head.id)) }
                            .opacity(filter.matches(head) ? 1 : skin.opacity.o35)
                    } else {
                        Text("routed by the CEO").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    }
                }
                ForEach(department.teams) { team in
                    TeamPanel(store: store, model: model, team: team, filter: filter)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }
}

private struct TeamPanel: View {
    let store: CitadelStore
    let model: CompanyModel
    let team: TeamInfo
    let filter: OrgFilter
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    private var project: ProjectInfo? { model.projects.first { $0.teamID == team.id } }

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                HStack(spacing: skin.size.s8) {
                    Text(team.name).citadelFont("t13", weight: "semibold").foregroundStyle(
                        skin.color(skin.text.primary))
                    if let project {
                        (Text("· project ").foregroundStyle(skin.color(skin.text.faint))
                            + Text(project.key).foregroundStyle(theme.accentSecondary)
                            .font(skin.font(AinkradFontToken(sizeKey: "t12", mono: "family"))))
                            .citadelFont("t12")
                    }
                    Spacer(minLength: skin.size.s8)
                    if let badge { AinkradBadge(text: badge, tint: theme.accentSecondary) }
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: skin.size.s190), spacing: skin.size.s4, alignment: .leading)],
                    alignment: .leading, spacing: skin.size.s4
                ) {
                    ForEach(team.seats, id: \.agentID) { seat in
                        if let agent = model.agents[seat.agentID] {
                            AgentRow(store: store, model: model, agent: agent, seat: seat)
                                .opacity(filter.matches(agent) ? 1 : skin.opacity.o35)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// `Sprint S4 · day 6`, or the project's flow.
    private var badge: String? {
        guard let project else { return nil }
        if let sprint = model.sprint, sprint.projectKey == project.key {
            let day = sprint.startsOn.map {
                (Calendar.current.dateComponents([.day], from: $0, to: Date()).day ?? 0) + 1
            }
            return "\(Wording.sprint(key: nil, name: sprint.name))\(day.map { " · day \($0)" } ?? "")"
        }
        return project.mode
    }
}

enum OrgMenu {
    static func items(_ agent: AgentInfo, open: (() -> Void)? = nil) -> [AinkradMenuItem] {
        var items: [AinkradMenuItem] = []
        if let open { items.append(AinkradMenuItem(title: "Open", systemName: "person", action: open)) }
        items.append(
            AinkradMenuItem(title: "Copy id", systemName: "doc.on.doc") {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(String(agent.id), forType: .string)
            })
        return items
    }
}
