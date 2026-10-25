import AinkradAppKit
import SwiftUI

/// The chart at zoom 1 (prototype `org.js` render): soft violet curves, the CEO node, each department's node and
/// its team clusters of agent bubbles, every cluster ending in a dashed Add.
struct OrgWorld: View {
    let store: CitadelStore
    let model: CompanyModel
    let layout: OrgLayout
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let page = model.orgPage
        ZStack(alignment: .topLeading) {
            Path { path in
                for (a, b) in layout.connectors {
                    let mid = (a.y + b.y) / 2
                    path.move(to: a)
                    path.addCurve(to: b, control1: CGPoint(x: a.x, y: mid), control2: CGPoint(x: b.x, y: mid))
                }
            }
            .stroke(skin.color(skin.palette.accentViolet).opacity(skin.opacity.o40), lineWidth: 1.5)
            .allowsHitTesting(false)
            if let ceo = model.ceo {
                OrgNode(isCEO: true, isSelected: page.picked == ceo.id, isDimmed: !page.filter.matches(ceo)) {
                    AgentFigure(agent: ceo, model: model, size: skin.size.s48, isActive: true)
                    NodeText(title: ceo.name, line: Text("CEO · \(ceo.model)"))
                    Text(Wording.count(max(0, model.agents.count - 1), "agent")).citadelFont("t11", mono: true)
                        .foregroundStyle(skin.color(skin.text.muted))
                } tap: {
                    page.picked = ceo.id
                }
                .ainkradContextMenu(AgentMenu.items(store: store, model: model, agent: ceo))
                .frame(width: OrgLayout.ceoW, height: OrgLayout.ceoH)
                .offset(x: layout.cx - OrgLayout.ceoW / 2)
            }
            ForEach(Array(zip(model.departments, layout.departments)), id: \.0.id) { department, laid in
                DepartmentNode(store: store, model: model, department: department)
                    .frame(width: OrgLayout.depW, height: OrgLayout.depH)
                    .offset(x: laid.cx - OrgLayout.depW / 2, y: OrgLayout.y1)
                ForEach(Array(zip(department.teams, laid.teams)), id: \.0.id) { team, box in
                    TeamCluster(store: store, model: model, team: team, cols: box.cols)
                        .frame(width: box.width, height: box.height, alignment: .top)
                        .offset(x: box.x, y: OrgLayout.y2)
                }
            }
        }
        .animation(skin.animation(skin.motion.hover), value: page.filter)
    }
}

/// A CEO or department card on the chart: lifts 2 pt on hover, a blue rim when picked, dims under a filter.
struct OrgNode<Content: View>: View {
    var isCEO = false
    var isSelected = false
    var isDimmed = false
    @ViewBuilder let content: Content
    let tap: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        let violet = skin.color(skin.palette.accentViolet)
        HStack(spacing: skin.size.s12) { content }
            .padding(.leading, skin.size.s12)
            .padding(.trailing, skin.size.s16)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(
                shape.fill(
                    isCEO
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [violet.opacity(skin.opacity.o50), violet.opacity(skin.opacity.o20)],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(skin.color(.palette("background", skin.opacity.o92))))
            )
            .background(shape.fill(skin.color(.palette("background", skin.opacity.o85))))
            .overlay(
                shape.strokeBorder(
                    isSelected
                        ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o60)
                        : hovering
                            ? skin.color(.palette("foreground", skin.opacity.o20))
                            : isCEO
                                ? violet.opacity(skin.opacity.o45)
                                : skin.color(.palette("foreground", skin.opacity.o10)),
                    lineWidth: 1)
            )
            .shadow(color: skin.color(.palette("black", skin.opacity.o30)), radius: skin.size.s12, y: skin.size.s8)
            .contentShape(shape)
            .offset(y: hovering && !reduceMotion ? -skin.size.s2 : 0)
            .opacity(isDimmed ? skin.opacity.o20 : 1)
            .saturation(isDimmed ? 0.2 : 1)
            .onHover { hovering = $0 }
            .onTapGesture(perform: tap)
            .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

struct NodeText: View {
    let title: String
    let line: Text
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s1) {
            Text(title).citadelFont("t14", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
            line.citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

private struct DepartmentNode: View {
    let store: CitadelStore
    let model: CompanyModel
    let department: DepartmentInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let page = model.orgPage
        let head = model.head(of: department)
        let busy = department.agentIDs.compactMap { model.agents[$0] }.filter { OrgBucket($0) == .busy }.count
        OrgNode(
            isSelected: head.map { page.picked == $0.id } ?? false,
            isDimmed: head.map { !page.filter.matches($0) } ?? false
        ) {
            if let head {
                AgentFigure(agent: head, model: model, size: skin.size.s40)
            } else {
                InitialTile(letter: department.name, side: skin.size.s40)
            }
            NodeText(
                title: department.name,
                line: head.map { Text("head · \($0.name), \($0.role)") }
                    ?? Text("no head — assign one").foregroundStyle(status.warning))
            HStack(spacing: skin.size.s8) {
                if busy > 0 {
                    HStack(spacing: skin.size.s5) {
                        Circle().fill(skin.color(skin.palette.accentSecondary)).frame(
                            width: skin.size.s7, height: skin.size.s7
                        )
                        .shadow(color: skin.color(skin.palette.accentSecondary), radius: skin.size.s4)
                        Text("\(busy)")
                    }
                }
                Text("\(department.agentIDs.count)")
                    .frame(minWidth: skin.size.s24, minHeight: skin.size.s22)
                    .padding(.horizontal, skin.size.s2)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o07)),
                        in: RoundedRectangle(cornerRadius: skin.size.s6))
            }
            .citadelFont("t11", mono: true)
            .foregroundStyle(skin.color(skin.text.muted))
        } tap: {
            if let head { page.picked = head.id } else { page.sheet = .department(department.id) }
        }
        .ainkradContextMenu(head.map { AgentMenu.items(store: store, model: model, agent: $0) } ?? [])
    }
}

/// A department's initial on violet, when it has no head (and on Structure cards).
struct InitialTile: View {
    let letter: String
    let side: CGFloat
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(String(letter.prefix(1)).uppercased()).citadelFont(side > skin.size.s30 ? "t14" : "t12", weight: "bold")
            .foregroundStyle(skin.color(skin.palette.accentViolet))
            .frame(width: side, height: side)
            .background(
                skin.color(skin.palette.accentViolet).opacity(skin.opacity.o16),
                in: RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
    }
}

/// `CIT` on violet (`.h-key`).
struct KeyChip: View {
    let key: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(key).citadelFont("t9_5", weight: "semibold", mono: true)
            .foregroundStyle(skin.color(skin.palette.accentViolet))
            .padding(.horizontal, skin.size.s5)
            .frame(minWidth: skin.size.s30, minHeight: skin.size.s22)
            .background(
                skin.color(skin.palette.accentViolet).opacity(skin.opacity.o14),
                in: RoundedRectangle(cornerRadius: skin.size.s6))
    }
}

private struct TeamCluster: View {
    let store: CitadelStore
    let model: CompanyModel
    let team: TeamInfo
    let cols: Int
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        let lead = model.lead(of: team)
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: skin.size.s8) {
                if let project = model.project(of: team) { KeyChip(key: project.key) }
                Text(team.name).citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(1)
                Spacer(minLength: skin.size.s4)
                if let lead {
                    Text("★ \(lead.name)").citadelFont("t11").foregroundStyle(status.warning)
                        .padding(.horizontal, skin.size.s8).frame(height: skin.size.s22)
                        .background(
                            status.warning.opacity(skin.opacity.o12), in: RoundedRectangle(cornerRadius: skin.size.s6))
                } else {
                    AinkradTapArea {
                        model.orgPage.sheet = .team(team.id)
                    } label: {
                        Text("★ assign lead").citadelFont("t11").foregroundStyle(status.warning)
                            .padding(.horizontal, skin.size.s8).frame(height: skin.size.s22)
                            .overlay(
                                RoundedRectangle(cornerRadius: skin.size.s6).strokeBorder(
                                    status.warning.opacity(skin.opacity.o45),
                                    style: StrokeStyle(lineWidth: 1, dash: [skin.size.s3, skin.size.s2])))
                    }
                    .buttonStyle(.plain)
                }
                if let cadence = model.cadence(of: team) {
                    AinkradStatePill(
                        text: cadence.text,
                        tint: cadence.isSprint ? skin.color(skin.palette.accentSecondary) : skin.color(skin.text.muted))
                }
            }
            .frame(height: OrgLayout.head)
            LazyVGrid(
                columns: Array(repeating: GridItem(.fixed(OrgLayout.cell), spacing: 0), count: cols),
                alignment: .leading, spacing: 0
            ) {
                ForEach(team.seats, id: \.agentID) { seat in
                    if let agent = model.agents[seat.agentID] {
                        AgentBubble(store: store, model: model, agent: agent, isLead: seat.teamRole == "team_lead")
                            .frame(height: OrgLayout.rowH, alignment: .top)
                    }
                }
                AddBubble(team: team.name) { model.orgPage.sheet = .hire(team: team.id, step: 0) }
                    .frame(height: OrgLayout.rowH, alignment: .top)
            }
        }
        .padding(.horizontal, OrgLayout.pad)
        .background(shape.fill(skin.color(.palette("background", skin.opacity.o90))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
        .shadow(color: skin.color(.palette("black", skin.opacity.o25)), radius: skin.size.s12, y: skin.size.s8)
    }
}

/// One agent on the chart: figure 44 ringed by its state, name, ROLE; ★ for the lead; picks into the peek panel.
struct AgentBubble: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    let isLead: Bool
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let page = model.orgPage
        let bucket = OrgBucket(agent)
        let selected = page.picked == agent.id
        let dimmed = !page.filter.matches(agent)
        VStack(spacing: skin.size.s2) {
            AgentFigure(agent: agent, model: model, size: skin.size.s44, isActive: bucket == .busy || hovering)
                .opacity(bucket == .pending ? skin.opacity.o60 : 1)
                .overlay { ring(bucket) }
                .overlay(alignment: .top) {
                    if isLead {
                        Text("★").citadelFont("t10").foregroundStyle(skin.color(skin.palette.warning))
                            .frame(width: skin.size.s18, height: skin.size.s18)
                            .background(
                                skin.color(.palette("black", skin.opacity.o85)),
                                in: RoundedRectangle(cornerRadius: skin.size.s6)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: skin.size.s6).strokeBorder(
                                    skin.color(skin.palette.warning).opacity(skin.opacity.o50), lineWidth: 1)
                            )
                            .offset(x: skin.size.s20, y: -skin.size.s2)
                    }
                }
                .padding(.bottom, skin.size.s3)
            Text(agent.name).citadelFont("t11", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                .lineLimit(1).frame(maxWidth: skin.size.s70)
            Text(agent.role.uppercased()).citadelFont("t9_5", weight: "semibold").tracking(0.5)
                .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
        }
        .padding(.top, skin.size.s4)
        .frame(width: OrgLayout.cell, height: OrgLayout.rowH - skin.size.s8, alignment: .top)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous).fill(
                selected
                    ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o16)
                    : skin.color(.palette("foreground", hovering ? skin.opacity.o06 : 0)))
        )
        .opacity(dimmed ? skin.opacity.o20 : bucket == .away ? skin.opacity.o55 : 1)
        .saturation(dimmed ? 0.2 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture { page.picked = agent.id }
        .ainkradContextMenu(AgentMenu.items(store: store, model: model, agent: agent))
        .help("\(agent.name) · \(agent.role)\(isLead ? " · team lead" : "") · \(bucket.label)")
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    @ViewBuilder private func ring(_ bucket: OrgBucket) -> some View {
        switch bucket {
        case .warn, .bad:
            let tint = bucket.tint(skin)
            Circle().strokeBorder(tint.opacity(skin.opacity.o70), lineWidth: 2)
                .shadow(color: tint.opacity(skin.opacity.o35), radius: skin.size.s7)
        case .pending:
            Circle().strokeBorder(skin.color(skin.palette.accentViolet).opacity(skin.opacity.o60), lineWidth: 1.5)
        default: EmptyView()
        }
    }
}

private struct AddBubble: View {
    let team: String
    let add: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(spacing: skin.size.s2) {
            Text("＋").citadelFont("t13")
                .foregroundStyle(hovering ? skin.color(skin.palette.accentPrimary) : skin.color(skin.text.muted))
                .frame(width: skin.size.s44, height: skin.size.s44)
                .overlay(
                    Circle().strokeBorder(
                        hovering
                            ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o60)
                            : skin.color(.palette("foreground", skin.opacity.o20)),
                        style: StrokeStyle(lineWidth: 1.5, dash: [skin.size.s4, skin.size.s3]))
                )
                .padding(.bottom, skin.size.s3)
            Text("Add").citadelFont("t11", weight: "medium").foregroundStyle(skin.color(skin.text.faint))
        }
        .padding(.top, skin.size.s4)
        .frame(width: OrgLayout.cell, alignment: .top)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: add)
        .help("Add an agent to \(team)")
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}
