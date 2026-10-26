import AinkradAppKit
import SwiftUI

/// The Overview bento (`.pjb`): burndown (or flow on Kanban) beside the agents' proposals, open issues beside the
/// teams, then the repositories as merge-order lanes.
struct ProjectOverview: View {
    let store: CitadelStore
    let facts: ProjectFacts
    @State private var width: CGFloat = 0
    @State private var showsHistory = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let left = max(0, (width - skin.size.s14) * 1.3 / 3.3)
        VStack(alignment: .leading, spacing: skin.size.s14) {
            row(left) {
                if facts.isScrum, facts.burndown != nil { burndown } else { flow }
            } second: {
                ProposalsTile(store: store, facts: facts) { showsHistory = true }
            }
            .ainkradRiseIn(delay: 0)
            row(left) {
                issues
            } second: {
                teams
            }
            .ainkradRiseIn(delay: 0.04)
            repos.ainkradRiseIn(delay: 0.08)
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .ainkradSheet(isPresented: $showsHistory) {
            ProfileHistorySheet(model: facts.model, project: facts.project, isPresented: $showsHistory)
        }
    }

    private func row(_ left: CGFloat, @ViewBuilder first: () -> some View, @ViewBuilder second: () -> some View)
        -> some View
    {
        HStack(alignment: .top, spacing: skin.size.s14) {
            first().frame(width: left > 0 ? left : nil).frame(maxHeight: .infinity)
            second().frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    // MARK: - Burndown / flow

    private var burndown: some View {
        AinkradBentoTile {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                OverviewHead(title: "Burndown · \(facts.active?.name ?? "")") {
                    Text("\(facts.report?.left ?? 0) pts left").citadelFont("t11", mono: true).foregroundStyle(
                        skin.color(skin.text.faint))
                }
                if let burndown = facts.burndown, let report = facts.report {
                    BurndownChart(left: burndown.left, committed: report.committed, days: burndown.days)
                        .frame(minHeight: skin.size.s128).frame(maxHeight: .infinity)
                }
                HStack(spacing: skin.size.s14) {
                    ProjectLegend(tint: skin.color(skin.palette.accentSecondary), label: "ideal", dashed: true)
                    ProjectLegend(tint: skin.color(skin.palette.accentSecondary), label: "remaining")
                    ProjectLegend(tint: skin.color(.palette("foreground", skin.opacity.o40)), label: "today")
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .frame(maxHeight: .infinity)
    }

    private var flow: some View {
        AinkradBentoTile {
            VStack(alignment: .leading, spacing: skin.size.s12) {
                OverviewHead(title: "Flow") { EmptyView() }
                FlowBar(flow: facts.work.flow, thickness: skin.size.s22)
                AinkradFlowLayout(spacing: skin.size.s14, lineSpacing: skin.size.s6) {
                    ForEach(facts.work.flow, id: \.state) { part in
                        HStack(spacing: skin.size.s6) {
                            RoundedRectangle(cornerRadius: skin.size.s2).fill(
                                ProjectLook.flowTint(part.state, skin: skin)
                            )
                            .frame(width: skin.size.s8, height: skin.size.s8)
                            Text("\(ProjectLogic.title(part.state)) \(part.count)").citadelFont("t11").foregroundStyle(
                                skin.color(skin.text.muted))
                        }
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Open issues

    private var issues: some View {
        let open = ProjectLogic.ranked(facts.work.open)
        return AinkradBentoTile {
            VStack(alignment: .leading, spacing: skin.size.s4) {
                OverviewHead(title: "Open issues", count: open.count) {
                    TileLink("Runs →") { store.screen = .runs }
                }
                .padding(.bottom, skin.size.s6)
                ForEach(open.prefix(6)) { item in
                    HoverRow(height: skin.size.s34) {
                        facts.page.drawer = .item(item.id)
                        store.openItem(item.id)
                    } content: {
                        RoundedRectangle(cornerRadius: skin.size.s2).fill(
                            ProjectLook.flowTint(ProjectLogic.flowState(item.state) ?? "", skin: skin)
                        )
                        .frame(width: skin.size.s8, height: skin.size.s8)
                        Text(item.key).citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.palette.accentSecondary))
                        Text(item.title).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                        Spacer(minLength: skin.size.s8)
                        if let agent = item.ownerAgentID.flatMap({ facts.model.agents[$0] }) {
                            AgentFigure(agent: agent, model: facts.model, size: skin.size.s18)
                        }
                        Text(item.points.map(String.init) ?? "–").citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.text.faint))
                    }
                }
                if open.isEmpty {
                    Text("Nothing open.").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    // MARK: - Teams

    private var teams: some View {
        AinkradBentoTile {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                OverviewHead(title: "Teams", count: facts.teams.count) {
                    TileLink("Manage →") { facts.page.drawer = .config(.teams) }
                }
                ForEach(Array(facts.teams.enumerated()), id: \.element.id) { index, team in
                    HStack(spacing: skin.size.s8) {
                        KeyBadge(text: facts.project.key)
                        Text(team.name).citadelFont("t12_5", weight: "bold").foregroundStyle(
                            skin.color(skin.text.primary))
                        if index == 0 { OwnerBadge() }
                        Spacer(minLength: skin.size.s8)
                        Text("\(team.seats.count) agents").citadelFont("t11").foregroundStyle(
                            skin.color(skin.text.faint))
                    }
                    .padding(.top, skin.size.s4)
                    LazyVGrid(
                        columns: [GridItem(.adaptive(minimum: skin.size.s80), spacing: skin.size.s6)],
                        spacing: skin.size.s6
                    ) {
                        ForEach(team.seats, id: \.agentID) { seat in
                            if let agent = facts.model.agents[seat.agentID] { cell(agent, seat: seat) }
                        }
                        TeamCell(
                            busy: false,
                            action: {
                                facts.model.orgPage.sheet = .hire(team: team.id, step: 0)
                                store.screen = .org
                            }
                        ) {
                            Text("＋").citadelFont("t13").foregroundStyle(skin.color(skin.text.muted))
                                .frame(width: skin.size.s34, height: skin.size.s34)
                                .overlay(
                                    Circle().strokeBorder(
                                        skin.color(.palette("foreground", skin.opacity.o20)),
                                        style: StrokeStyle(lineWidth: 1.5, dash: [skin.size.s3])))
                            Text("Add").citadelFont("t11", weight: "bold").foregroundStyle(
                                skin.color(skin.text.primary))
                            Text(" ").citadelFont("t10")
                        }
                        .help("Propose an agent for \(team.name) (Org → hire)")
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
    }

    private func cell(_ agent: AgentInfo, seat: SeatInfo) -> some View {
        let busy = facts.busy.contains { $0.id == agent.id }
        return TeamCell(busy: busy, action: { store.open(.agent(agent.id)) }) {
            AgentFigure(agent: agent, model: facts.model, size: skin.size.s34, isActive: busy)
            Text(agent.name).citadelFont("t11", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                .lineLimit(1)
            Text(seat.teamRole == "team_lead" ? "★ lead" : agent.role).citadelFont("t10").foregroundStyle(
                skin.color(skin.text.faint)
            ).lineLimit(1)
        }
    }

    // MARK: - Repositories

    private var repos: some View {
        AinkradBentoTile(onTap: { facts.page.drawer = .config(.repos) }) {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                OverviewHead(title: "Repositories · merge order") {
                    TileLink("Configure →") { facts.page.drawer = .config(.repos) }
                }
                if facts.repos.isEmpty {
                    Text("No repository — this project's agents only write docs and posts.").citadelFont("t12")
                        .foregroundStyle(skin.color(skin.text.faint))
                } else {
                    ScrollView(.horizontal) {
                        HStack(alignment: .center, spacing: skin.size.s10) {
                            ForEach(Array(facts.repos.enumerated()), id: \.element.id) { index, repo in
                                if index > 0 { Text("→").foregroundStyle(skin.color(skin.text.faint)) }
                                lane(repo, number: index + 1)
                            }
                        }
                    }
                    .scrollIndicators(.never)
                }
            }
        }
    }

    private func lane(_ repo: RepoInfo, number: Int) -> some View {
        HStack(alignment: .top, spacing: skin.size.s12) {
            LaneNumber(number: number)
            VStack(alignment: .leading, spacing: skin.size.s2) {
                (Text(repo.name) + Text(repo.isPrimary ? " ★" : "").foregroundStyle(skin.color(skin.palette.warning)))
                    .citadelFont("t12_5", weight: "semibold", mono: true).foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(1)
                // Each repo's own stack from API minor 18; before, only the primary's, from the profile.
                if let stack = facts.hasTrancheB ? repo.stack : (repo.isPrimary ? facts.profile?.stack : nil),
                    !stack.isEmpty
                {
                    Text(stack).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(2)
                }
                HStack(spacing: skin.size.s8) {
                    Text("⑂ \(repo.defaultBranch)").citadelFont("t10_5").foregroundStyle(skin.color(skin.text.muted))
                    if facts.hasTrancheB, !repo.inUseBy.isEmpty {
                        Text("in use by \(repo.inUseBy.joined(separator: ", "))").citadelFont("t10_5", mono: true)
                            .foregroundStyle(skin.color(skin.palette.accentSecondary)).lineLimit(1)
                    }
                }
                .padding(.top, skin.size.s6)
            }
            Spacer(minLength: 0)
        }
        .padding(skin.size.s12)
        .frame(minWidth: skin.size.s220, maxWidth: .infinity, alignment: .leading)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s14).strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o08))))
    }
}

/// A bento header (`.bt-h`): uppercase label, optional count badge, a trailing slot.
struct OverviewHead<Trailing: View>: View {
    let title: String
    var count: Int?
    var countTint: Color?
    @ViewBuilder let trailing: Trailing
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s8) {
            Text(skin.labelCased(title)).citadelFont("t10_5", weight: "semibold").foregroundStyle(
                skin.color(skin.text.muted))
            if let count {
                Text("\(count)").citadelFont("t10", weight: "semibold", mono: true)
                    .foregroundStyle(countTint ?? skin.color(skin.text.primary))
                    .padding(.horizontal, skin.size.s6).padding(.vertical, skin.size.s1)
                    .background(
                        (countTint ?? skin.color(.palette("foreground", 1))).opacity(
                            countTint == nil ? skin.opacity.o07 : skin.opacity.o20), in: Capsule())
            }
            Spacer(minLength: skin.size.s8)
            trailing
        }
    }
}

/// `Runs →` in cyan mono (`.key` link).
struct TileLink: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        AinkradTapArea(action: action) {
            Text(title).citadelFont("t11", weight: "medium", mono: true).foregroundStyle(
                skin.color(skin.palette.accentSecondary)
            ).underline(hovering)
        }
        .citadelHover($hovering)
    }
}

/// A row that washes on hover (`.iss-r`).
struct HoverRow<Content: View>: View {
    let height: CGFloat
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(action: action) {
            HStack(spacing: skin.size.s8) { content }
                .padding(.horizontal, skin.size.s8)
                .frame(height: height)
                .background(
                    skin.color(.palette("foreground", hovering ? skin.opacity.o05 : 0)),
                    in: RoundedRectangle(cornerRadius: skin.size.s9)
                )
                .contentShape(Rectangle())
        }
        .padding(.horizontal, -skin.size.s8)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// A team member cell (`.tg`): cyan when busy, lifts on hover.
private struct TeamCell<Content: View>: View {
    let busy: Bool
    let action: () -> Void
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(action: action) {
            VStack(spacing: skin.size.s2) { content }
                .frame(maxWidth: .infinity)
                .padding(.vertical, skin.size.s8).padding(.horizontal, skin.size.s4)
                .background(
                    busy
                        ? skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o07)
                        : skin.color(.palette("foreground", hovering ? skin.opacity.o05 : 0)),
                    in: RoundedRectangle(cornerRadius: skin.size.s12))
        }
        .modifier(LiftModifier(hovering: hovering))
        .onHover { hovering = $0 }
    }
}

private struct LiftModifier: ViewModifier {
    let hovering: Bool
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    func body(content: Content) -> some View {
        content.offset(y: hovering && !reduceMotion ? -skin.size.s2 : 0).animation(
            skin.animation(skin.motion.hover), value: hovering)
    }
}

/// `CIT` (`.h-key`).
struct KeyBadge: View {
    let text: String
    @Environment(\.ainkradSkin) private var skin
    var body: some View {
        Text(text).citadelFont("t10", weight: "bold", mono: true).foregroundStyle(
            skin.color(skin.palette.accentPrimary)
        )
        .padding(.horizontal, skin.size.s5).padding(.vertical, skin.size.s2)
        .background(
            skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o16),
            in: RoundedRectangle(cornerRadius: skin.size.s5))
    }
}

/// `owner` (`.tm-own`).
struct OwnerBadge: View {
    @Environment(\.ainkradSkin) private var skin
    var body: some View {
        Text("owner").citadelFont("t10").foregroundStyle(skin.color(skin.palette.warning))
            .padding(.horizontal, skin.size.s6).padding(.vertical, skin.size.s1)
            .background(
                skin.color(skin.palette.warning).opacity(skin.opacity.o14),
                in: RoundedRectangle(cornerRadius: skin.size.s5))
    }
}

/// The 28 pt merge-order number (`.lane-n`).
struct LaneNumber: View {
    let number: Int
    @Environment(\.ainkradSkin) private var skin
    var body: some View {
        Text("\(number)").citadelFont("t12", weight: "semibold", mono: true).foregroundStyle(
            skin.color(skin.palette.accentPrimary)
        )
        .frame(width: skin.size.s28, height: skin.size.s28)
        .background(
            skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o18),
            in: RoundedRectangle(cornerRadius: skin.size.s9))
    }
}
