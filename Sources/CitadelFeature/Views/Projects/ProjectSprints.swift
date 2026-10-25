import AinkradAppKit
import SwiftUI

/// The Sprints tab (`quest-plan.js` `qSprintsView`): the active sprint, capacity per agent, velocity and every
/// sprint. A Kanban project shows why there are none.
struct ProjectSprints: View {
    let store: CitadelStore
    let facts: ProjectFacts
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let work = facts.work
        if !facts.isScrum || work.sprints.isEmpty {
            VStack(spacing: skin.size.s6) {
                Text("⇶").citadelFont("t16").foregroundStyle(skin.color(skin.palette.success))
                    .frame(width: skin.size.s36, height: skin.size.s36)
                    .background(
                        skin.color(skin.palette.success).opacity(skin.opacity.o14),
                        in: RoundedRectangle(cornerRadius: skin.size.s11))
                Text(facts.isScrum ? "No sprints yet" : "\(facts.project.name) runs on Kanban").citadelFont(
                    "t13", weight: "bold"
                )
                .foregroundStyle(skin.color(skin.text.primary))
                Text(
                    facts.isScrum
                        ? "Plan the first one — the PO and lead fill it from the backlog."
                        : "No sprints — work flows continuously on the board. Switch to sprints in the project's Rules."
                )
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                if facts.isScrum {
                    AinkradButton(title: "Plan a sprint", style: .primary) {
                        store.planNextSprint(project: facts.project.id)
                    }.compact().fixedSize()
                }
            }
            .frame(maxWidth: .infinity).padding(.vertical, skin.size.s60)
        } else {
            PickGrid(columns: 2, spacing: skin.size.s14) {
                if let active = work.active { current(active) }
                capacity
                velocity
                all
            }
        }
    }

    // MARK: - Active

    private func current(_ sprint: SprintDetail) -> some View {
        let report = facts.report
        let items = facts.work.items(in: sprint.id)
        let blocked = items.filter(\.isBlocked).count
        let days = sprint.day()
        return BentoTile {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                OverviewHead(title: "Sprint \(sprint.name) · active") {
                    Text(sprint.range).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                }
                Text(sprint.goal.isEmpty ? "No goal set" : sprint.goal).citadelFont("t15", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.primary))
                HStack(spacing: skin.size.s18) {
                    AinkradRingGauge(
                        value: report?.fraction ?? 0, tint: skin.color(skin.palette.accentSecondary),
                        diameter: skin.size.s80, lineWidth: skin.size.s8
                    ) {
                        Text("\(Int((report?.fraction ?? 0) * 100))%").citadelFont(
                            "t12", weight: "semibold", mono: true
                        )
                        .foregroundStyle(skin.color(skin.text.primary))
                    }
                    Grid(alignment: .leading, horizontalSpacing: skin.size.s10, verticalSpacing: skin.size.s10) {
                        GridRow {
                            kpi(
                                Text("\(report?.completed ?? 0)")
                                    + Text("/\(report?.committed ?? 0)").font(small).foregroundStyle(
                                        skin.color(skin.text.muted)), "points done")
                            kpi(Text(days.map { "\(max(0, $0.of - $0.day))" } ?? "—"), "days left")
                        }
                        GridRow {
                            kpi(Text("\(items.filter(\.isOpen).count)"), "items open")
                            kpi(
                                Text("\(blocked)").foregroundStyle(
                                    blocked > 0 ? skin.color(skin.palette.danger) : skin.color(skin.text.primary)),
                                "blocked")
                        }
                    }
                    .frame(maxWidth: .infinity, alignment: .leading)
                }
                if let burndown = facts.burndown, let report {
                    BurndownChart(left: burndown.left, committed: report.committed, days: burndown.days).frame(
                        height: skin.size.s110)
                }
            }
        }
    }

    private var small: Font { skin.font(AinkradFontToken(sizeKey: "t12")) }

    private func kpi(_ value: Text, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            value.citadelFont("t20", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
            Text(label).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        }
    }

    // MARK: - Capacity

    private var capacity: some View {
        let sprint = facts.work.active
        let scale = max(16, facts.work.capacity.values.max() ?? 0)
        return BentoTile {
            VStack(alignment: .leading, spacing: 0) {
                OverviewHead(title: "Capacity · \(sprint?.name ?? "")") {
                    Text("points per agent").citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                }
                .padding(.bottom, skin.size.s6)
                ForEach(facts.agents) { agent in
                    let mine = facts.work.items.filter { $0.sprintID == sprint?.id && $0.ownerAgentID == agent.id }
                    let planned = mine.reduce(0) { $0 + ($1.points ?? 0) }
                    let done = mine.filter(\.isDone).reduce(0) { $0 + ($1.points ?? 0) }
                    let cap = facts.work.capacity[agent.id]
                    HoverRow(height: skin.size.s40, action: { store.open(.agent(agent.id)) }) {
                        AgentFigure(agent: agent, model: facts.model, size: skin.size.s26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(agent.name).citadelFont("t12", weight: "bold").foregroundStyle(
                                skin.color(skin.text.primary))
                            Text("\(agent.role) · \(facts.team?.name ?? "")").citadelFont("t10_5").foregroundStyle(
                                skin.color(skin.text.faint)
                            ).lineLimit(1)
                        }
                        .frame(width: skin.size.s96, alignment: .leading)
                        CapacityBar(done: done, planned: planned, capacity: cap, scale: scale)
                        Text("\(planned)/\(cap.map(String.init) ?? "–")").citadelFont("t11", mono: true)
                            .foregroundStyle(
                                cap.map { planned > $0 } == true
                                    ? skin.color(skin.palette.danger) : skin.color(skin.text.faint)
                            )
                            .frame(width: skin.size.s40, alignment: .trailing)
                    }
                }
                HStack(spacing: skin.size.s14) {
                    ProjectLegend(tint: skin.color(skin.palette.success), label: "done")
                    ProjectLegend(tint: skin.color(skin.palette.accentSecondary), label: "open")
                    ProjectLegend(tint: skin.color(.palette("foreground", skin.opacity.o40)), label: "capacity")
                }
                .padding(.top, skin.size.s6)
            }
        }
    }

    // MARK: - Velocity

    private var velocity: some View {
        let work = facts.work
        var bars: [(name: String, committed: Int, done: Int, state: String)] = work.velocity.map { point in
            (
                work.sprints.first { $0.id == point.sprintID }?.name ?? "#\(point.sprintID)", point.committed,
                point.completed, "closed"
            )
        }
        if let active = work.active, let report = facts.report {
            bars.append((active.name, report.committed, report.completed, "active"))
        }
        if let next = work.next {
            bars.append((next.name, work.items(in: next.id).reduce(0) { $0 + ($1.points ?? 0) }, 0, "planned"))
        }
        let top = max(1, bars.map { max($0.committed, $0.done) }.max() ?? 1)
        return BentoTile {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                OverviewHead(title: "Velocity") {
                    Text("avg \(Int((work.velocityAverage ?? 0).rounded())) pts").citadelFont("t11", mono: true)
                        .foregroundStyle(skin.color(skin.text.faint))
                }
                VBars(
                    bars: bars.map {
                        VBar(
                            label: $0.name, value: $0.state == "planned" ? "next" : "\($0.done)",
                            back: Double($0.committed) / Double(top),
                            front: Double($0.done) / Double(top), highlight: $0.state == "active",
                            dim: $0.state == "planned")
                    }
                )
                .frame(height: skin.size.s150)
                HStack(spacing: skin.size.s14) {
                    ProjectLegend(tint: skin.color(.palette("foreground", skin.opacity.o18)), label: "committed")
                    ProjectLegend(tint: skin.color(skin.palette.accentSecondary), label: "done")
                }
            }
        }
    }

    // MARK: - All sprints

    private var all: some View {
        let work = facts.work
        return BentoTile {
            VStack(alignment: .leading, spacing: skin.size.s4) {
                OverviewHead(title: "All sprints") {
                    if let next = work.next {
                        AinkradButton(title: "Plan \(next.name)", style: .primary) { facts.page.tab = .backlog }
                            .compact().fixedSize()
                    } else {
                        AinkradButton(
                            title: "Plan \(CitadelStore.nextSprintName(after: work.sprints.last?.name))",
                            style: .primary
                        ) {
                            store.planNextSprint(project: facts.project.id)
                        }
                        .compact().fixedSize()
                    }
                }
                ForEach(work.sprints.reversed()) { sprint in
                    let points = work.velocity.first { $0.sprintID == sprint.id }
                    HStack(spacing: skin.size.s10) {
                        stateTile(sprint.state)
                        VStack(alignment: .leading, spacing: 0) {
                            Text("\(sprint.name)\(sprint.goal.isEmpty ? "" : " · \(sprint.goal)")").citadelFont(
                                "t12", weight: "medium"
                            )
                            .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                            Text(sprint.range).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                        }
                        Spacer(minLength: skin.size.s8)
                        Text(line(sprint, points)).citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.text.faint))
                    }
                    .padding(.vertical, skin.size.s9).padding(.horizontal, skin.size.s4)
                }
            }
        }
    }

    private func line(_ sprint: SprintDetail, _ points: VelocityPoint?) -> String {
        if sprint.state == "planned" {
            return "\(facts.work.items(in: sprint.id).reduce(0) { $0 + ($1.points ?? 0) }) pts planned"
        }
        if sprint.state == "active", let report = facts.report { return "\(report.completed)/\(report.committed) pts" }
        return points.map { "\($0.completed)/\($0.committed) pts" } ?? "—"
    }

    private func stateTile(_ state: String) -> some View {
        let (glyph, tint): (String, Color) =
            switch state {
            case "active": ("●", skin.color(skin.palette.accentSecondary))
            case "closed": ("✓", skin.color(skin.palette.success))
            default: ("○", skin.color(skin.text.muted))
            }
        return Text(glyph).citadelFont("t11").foregroundStyle(tint)
            .frame(width: skin.size.s24, height: skin.size.s24)
            .background(
                state == "planned"
                    ? skin.color(.palette("foreground", skin.opacity.o06)) : tint.opacity(skin.opacity.o14),
                in: RoundedRectangle(cornerRadius: skin.size.s7))
    }
}

/// Done (green) and open (cyan) points against a capacity tick, on a shared scale (`.cap-bar`).
private struct CapacityBar: View {
    let done: Int
    let planned: Int
    let capacity: Int?
    let scale: Int
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        GeometryReader { geo in
            let unit = geo.size.width / CGFloat(max(1, scale))
            ZStack(alignment: .leading) {
                Capsule().fill(skin.color(.palette("foreground", skin.opacity.o06)))
                HStack(spacing: 0) {
                    Rectangle().fill(skin.color(skin.palette.success)).frame(
                        width: min(geo.size.width, unit * CGFloat(done)))
                    Rectangle().fill(skin.color(skin.palette.accentSecondary)).frame(
                        width: min(geo.size.width, unit * CGFloat(max(0, planned - done))))
                }
                .clipShape(Capsule())
                if let capacity {
                    Capsule().fill(skin.color(.palette("foreground", skin.opacity.o40)))
                        .frame(width: skin.size.s2, height: skin.size.s16).offset(x: unit * CGFloat(capacity))
                }
            }
            .frame(height: skin.size.s10).frame(maxHeight: .infinity)
        }
        .frame(height: skin.size.s16)
    }
}

struct VBar {
    var label: String
    var value: String
    var back: Double
    var front: Double
    var highlight = false
    var dim = false
}

/// Bars that grow from the bottom, staggered (`.vel`): a committed bar behind a cyan done bar.
struct VBars: View {
    let bars: [VBar]
    @State private var grown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(alignment: .bottom, spacing: skin.size.s12) {
            ForEach(Array(bars.enumerated()), id: \.offset) { index, bar in
                VStack(spacing: skin.size.s4) {
                    GeometryReader { geo in
                        ZStack(alignment: .bottom) {
                            UnevenRoundedRectangle(
                                topLeadingRadius: skin.size.s6, bottomLeadingRadius: skin.size.s3,
                                bottomTrailingRadius: skin.size.s3, topTrailingRadius: skin.size.s6
                            )
                            .fill(skin.color(.palette("foreground", skin.opacity.o12)))
                            .frame(height: geo.size.height * bar.back)
                            UnevenRoundedRectangle(
                                topLeadingRadius: skin.size.s6, bottomLeadingRadius: skin.size.s3,
                                bottomTrailingRadius: skin.size.s3, topTrailingRadius: skin.size.s6
                            )
                            .fill(
                                LinearGradient(
                                    colors: [
                                        skin.color(skin.palette.accentSecondary),
                                        skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o40),
                                    ], startPoint: .top, endPoint: .bottom)
                            )
                            .frame(width: geo.size.width * 0.6, height: geo.size.height * bar.front)
                        }
                        .frame(maxWidth: skin.size.s46, maxHeight: .infinity, alignment: .bottom)
                        .frame(maxWidth: .infinity)
                        .scaleEffect(x: 1, y: grown || reduceMotion ? 1 : 0.001, anchor: .bottom)
                        .animation(
                            skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.7)).delay(
                                Double(index) * 0.08), value: grown)
                    }
                    Text(bar.label).citadelFont("t11", weight: "bold")
                        .foregroundStyle(
                            bar.highlight ? skin.color(skin.palette.accentSecondary) : skin.color(skin.text.primary))
                    Text(bar.value).citadelFont("t10", mono: true).foregroundStyle(skin.color(skin.text.faint))
                }
                .opacity(bar.dim ? skin.opacity.o55 : 1)
            }
        }
        .padding(.top, skin.size.s8)
        .onAppear { grown = true }
    }
}
