import AinkradAppKit
import SwiftUI

/// The bento board (prototype `agent.js` agentBento): Now spans the first column; budget burn, success, when it
/// works, chain and skills fill the other two. Below ~900 pt it folds to two columns with Now on top.
struct AgentBento: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    let wide: Bool
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let gap = skin.size.s14
        let runs = model.agentRuns[agent.id] ?? []
        let stats = AgentStats(runs: runs)
        let right = VStack(spacing: gap) {
            HStack(alignment: .top, spacing: gap) {
                BurnTile(model: model, agent: agent, runs: runs)
                SuccessTile(store: store, stats: stats)
            }
            .fixedSize(horizontal: false, vertical: true)
            HStack(alignment: .top, spacing: gap) {
                HeatTile(stats: stats)
                ChainTile(store: store, model: model, agent: agent)
            }
            .fixedSize(horizontal: false, vertical: true)
            SkillsTile(model: model, agent: agent)
        }
        if wide {
            GeometryReader { geo in
                let unit = (geo.size.width - gap * 2) / 3.25
                HStack(alignment: .top, spacing: gap) {
                    NowTile(store: store, model: model, agent: agent).frame(width: unit * 1.25)
                        .frame(maxHeight: .infinity)
                    right
                }
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    height = $0
                }
            }
            .frame(height: height)
        } else {
            VStack(spacing: gap) {
                NowTile(store: store, model: model, agent: agent)
                right
            }
        }
    }

    @State private var height: CGFloat = 520
}

/// A bento tile (`.bt`): r18, faint fill, lifts on hover when it opens something.
struct BentoBox<Content: View>: View {
    var live = false
    var onTap: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        let cyan = skin.color(skin.palette.accentSecondary)
        VStack(alignment: .leading, spacing: skin.size.s10) { content }
            .padding(skin.size.s16)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
            .background(
                shape.fill(
                    live
                        ? AnyShapeStyle(
                            LinearGradient(
                                colors: [
                                    cyan.opacity(skin.opacity.o09),
                                    skin.color(.palette("foreground", skin.opacity.o03)),
                                ],
                                startPoint: .topLeading, endPoint: .bottomTrailing))
                        : AnyShapeStyle(
                            skin.color(.palette("foreground", hovering ? skin.opacity.o06 : skin.opacity.o05))))
            )
            .overlay(
                shape.strokeBorder(
                    live
                        ? cyan.opacity(skin.opacity.o35)
                        : skin.color(.palette("foreground", hovering ? skin.opacity.o14 : skin.opacity.o08)),
                    lineWidth: 1)
            )
            .contentShape(shape)
            .offset(y: hovering && !reduceMotion ? -skin.size.s2 : 0)
            .onHover { hovering = $0 }
            .onTapGesture { onTap?() }
            .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// `Label ……… trailing` at a tile's top (`.bt-h`).
struct BentoHead: View {
    let title: String
    var trailing: String?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s8) {
            Text(title).citadelFont("t10_5", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
            Spacer(minLength: skin.size.s8)
            if let trailing {
                Text(trailing).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
            }
        }
    }
}

private struct BurnTile: View {
    let model: CompanyModel
    let agent: AgentInfo
    let runs: [RunInfo]
    @State private var revealed = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let budget = model.monthBudget(of: agent.id)
        let calendar = Calendar.current
        let days = calendar.range(of: .day, in: .month, for: Date())?.count ?? 30
        let series = AgentStats.burn(runs: runs, spent: budget?.spent ?? 0)
        let projection = series.isEmpty ? 0 : (budget?.spent ?? 0) / Int64(series.count) * Int64(days)
        BentoBox(onTap: { model.orgPage.drawer = .init(section: .settings, anchor: "budget") }) {
            BentoHead(
                title: "Budget burn · \(Date().formatted(.dateTime.month(.wide)))",
                trailing: "day \(series.count)/\(days)")
            if let budget {
                HStack(alignment: .firstTextBaseline, spacing: skin.size.s6) {
                    Text(Fmt.tokens(budget.spent)).citadelFont("t24", weight: "bold")
                    Text("/ \(Fmt.tokens(budget.cap)) tok").citadelFont("t12", weight: "medium")
                        .foregroundStyle(skin.color(skin.text.muted))
                    Spacer()
                    let over = projection > budget.cap
                    Text("→ \(Fmt.tokens(projection)) by \(Date().formatted(.dateTime.month(.abbreviated))) \(days)")
                        .citadelFont("t11", weight: "medium")
                        .foregroundStyle(
                            over ? skin.color(skin.palette.warning) : skin.color(skin.palette.accentSecondary)
                        )
                        .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
                        .background(
                            (over ? skin.color(skin.palette.warning) : skin.color(skin.palette.accentSecondary))
                                .opacity(skin.opacity.o10),
                            in: RoundedRectangle(cornerRadius: skin.size.s6))
                }
                BurnChart(
                    series: series, days: days, cap: budget.cap, warn: budget.warnFraction, projection: projection
                )
                .frame(height: skin.size.s110)
                .mask(alignment: .leading) {
                    GeometryReader { geo in
                        Rectangle().frame(width: revealed || reduceMotion ? geo.size.width : 0)
                    }
                }
                .onAppear {
                    withAnimation(skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 1.2))) {
                        revealed = true
                    }
                }
                HStack(spacing: skin.size.s12) {
                    legend(
                        skin.color(skin.palette.warning),
                        "warn \(Fmt.tokens(budget.cap * Int64(budget.warnPercent) / 100))")
                    legend(
                        skin.color(skin.palette.danger),
                        budget.hardStop ? "hard stop \(Fmt.tokens(budget.cap))" : "cap \(Fmt.tokens(budget.cap))")
                    legend(skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o60), "projection")
                }
            } else {
                Text("No month budget — set one in Settings › Budget.").citadelFont("t12").foregroundStyle(
                    skin.color(skin.text.faint))
            }
        }
    }

    private func legend(_ color: Color, _ text: String) -> some View {
        HStack(spacing: skin.size.s5) {
            Capsule().fill(color).frame(width: skin.size.s10, height: skin.size.s2)
            Text(text)
        }
        .citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
    }
}

/// Cumulative spend over the month: warn line dashed amber, stop line red, area, line, dashed projection, tip.
private struct BurnChart: View {
    let series: [Int64]
    let days: Int
    let cap: Int64
    let warn: Double
    let projection: Int64
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Canvas { context, size in
            let top = max(Double(cap), Double(projection)) * 1.05
            func y(_ v: Double) -> CGFloat { size.height - 8 - CGFloat(v / max(top, 1)) * (size.height - 20) }
            func x(_ day: Int) -> CGFloat { CGFloat(day - 1) / CGFloat(max(1, days - 1)) * size.width }
            let cyan = skin.color(skin.palette.accentSecondary)
            var warnLine = Path()
            warnLine.move(to: CGPoint(x: 0, y: y(Double(cap) * warn)))
            warnLine.addLine(to: CGPoint(x: size.width, y: y(Double(cap) * warn)))
            context.stroke(
                warnLine, with: .color(skin.color(skin.palette.warning).opacity(skin.opacity.o60)),
                style: StrokeStyle(lineWidth: 1, dash: [3, 4]))
            var stop = Path()
            stop.move(to: CGPoint(x: 0, y: y(Double(cap))))
            stop.addLine(to: CGPoint(x: size.width, y: y(Double(cap))))
            context.stroke(stop, with: .color(skin.color(skin.palette.danger).opacity(skin.opacity.o60)), lineWidth: 1)
            guard !series.isEmpty else { return }
            var line = Path()
            for (i, v) in series.enumerated() {
                let p = CGPoint(x: x(i + 1), y: y(Double(v)))
                if i == 0 { line.move(to: p) } else { line.addLine(to: p) }
            }
            var area = line
            area.addLine(to: CGPoint(x: x(series.count), y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [cyan.opacity(skin.opacity.o32), cyan.opacity(0)]), startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(cyan), lineWidth: 2)
            let tip = CGPoint(x: x(series.count), y: y(Double(series.last ?? 0)))
            var proj = Path()
            proj.move(to: tip)
            proj.addLine(to: CGPoint(x: x(days), y: y(min(Double(projection), Double(cap) * 1.1))))
            context.stroke(
                proj, with: .color(cyan.opacity(skin.opacity.o55)), style: StrokeStyle(lineWidth: 1.5, dash: [4, 4]))
            let dot = Path(ellipseIn: CGRect(x: tip.x - 3.5, y: tip.y - 3.5, width: 7, height: 7))
            context.fill(dot, with: .color(cyan))
            context.stroke(dot, with: .color(skin.color(skin.palette.background)), lineWidth: 2)
        }
    }
}

private struct SuccessTile: View {
    let store: CitadelStore
    let stats: AgentStats
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let percent = stats.successPercent
        let good = (percent ?? 100) >= 80
        BentoBox(onTap: {
            store.screen = .runs
            store.detail = nil
        }) {
            BentoHead(title: "Success rate", trailing: "8 weeks")
            HStack(alignment: .center, spacing: skin.size.s16) {
                AinkradRingGauge(
                    value: percent.map { Double($0) / 100 },
                    tint: good ? skin.color(skin.palette.success) : skin.color(skin.palette.warning),
                    diameter: skin.size.s72, lineWidth: skin.size.s7
                ) {
                    Text(percent.map { "\($0)%" } ?? "—").citadelFont("t12", weight: "semibold", mono: true)
                }
                HStack(alignment: .bottom, spacing: skin.size.s5) {
                    ForEach(Array(stats.weekly.enumerated()), id: \.offset) { index, value in
                        let ok = (value ?? 0) >= 80
                        let tint = ok ? skin.color(skin.palette.success) : skin.color(skin.palette.warning)
                        RoundedRectangle(cornerRadius: skin.size.s4)
                            .fill(
                                value == nil
                                    ? AnyShapeStyle(skin.color(.palette("foreground", skin.opacity.o08)))
                                    : AnyShapeStyle(
                                        LinearGradient(
                                            colors: [tint.opacity(skin.opacity.o90), tint.opacity(skin.opacity.o35)],
                                            startPoint: .top, endPoint: .bottom))
                            )
                            .frame(height: value.map { skin.size.s72 * CGFloat(max(0, $0 - 35)) / 65 } ?? skin.size.s3)
                            .help(value.map { "week \(index + 1) · \($0)%" } ?? "week \(index + 1) · no runs")
                    }
                }
                .frame(height: skin.size.s72, alignment: .bottom)
            }
            Text("\(stats.retried) of \(stats.finished) recent runs needed a retry or a raise").citadelFont("t11")
                .foregroundStyle(skin.color(skin.text.faint))
        }
    }
}

private struct HeatTile: View {
    let stats: AgentStats

    var body: some View {
        BentoBox {
            BentoHead(title: "When it works", trailing: "this week")
            Heatmap(
                rows: ["Mon", "Tue", "Wed", "Thu", "Fri", "Sat", "Sun"], columns: ["00", "04", "08", "12", "16", "20"],
                values: stats.heat)
        }
    }
}

private struct ChainTile: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let boss = model.agent(agent.reportsTo)
        let reports = model.reports(of: agent.id)
        BentoBox {
            HStack {
                Text("Chain of command").citadelFont("t10_5", weight: "semibold").foregroundStyle(
                    skin.color(skin.text.muted))
                Spacer()
                AinkradTapArea {
                    store.open(nil)
                } label: {
                    Text("Org →").citadelFont("t11", mono: true).foregroundStyle(
                        skin.color(skin.palette.accentSecondary))
                }
                .buttonStyle(.plain)
            }
            VStack(alignment: .leading, spacing: 0) {
                if let boss {
                    node(boss, line: bossLine(boss), me: false)
                    connector.padding(.leading, skin.size.s20)
                }
                node(agent, line: myLine, me: true).padding(.leading, boss == nil ? 0 : skin.size.s22)
                if !reports.isEmpty {
                    connector.padding(.leading, skin.size.s42)
                    HStack(spacing: skin.size.s4) {
                        ForEach(reports.prefix(6)) { report in
                            AinkradTapArea {
                                store.open(.agent(report.id))
                            } label: {
                                AgentFigure(agent: report, model: model, size: skin.size.s22)
                            }
                            .buttonStyle(.plain)
                            .agentHoverCard(store, model, report)
                        }
                        Text(Wording.count(reports.count, "report")).citadelFont("t11").foregroundStyle(
                            skin.color(skin.text.faint)
                        )
                        .padding(.leading, skin.size.s8)
                    }
                    .padding(.leading, skin.size.s44)
                }
            }
        }
    }

    private var connector: some View {
        Rectangle().fill(skin.color(skin.palette.accentViolet).opacity(skin.opacity.o45))
            .frame(width: skin.size.s1_5, height: skin.size.s14)
    }

    private func bossLine(_ boss: AgentInfo) -> String {
        if let department = model.headedDepartment(of: boss.id) { return "head of \(department.name)" }
        if let (_, team) = model.team(of: agent.id), model.lead(of: team)?.id == boss.id { return "team lead" }
        return boss.role
    }

    private var myLine: String {
        if let (_, team) = model.team(of: agent.id), model.lead(of: team)?.id == agent.id { return "★ team lead" }
        return model.headedDepartment(of: agent.id) != nil ? "department head" : agent.role
    }

    private func node(_ who: AgentInfo, line: String, me: Bool) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        return AinkradTapArea {
            if !me { store.open(.agent(who.id)) }
        } label: {
            HStack(spacing: skin.size.s10) {
                AgentFigure(agent: who, model: model, size: me ? skin.size.s28 : skin.size.s24)
                VStack(alignment: .leading, spacing: 0) {
                    Text(who.name).citadelFont("t12_5", weight: "semibold")
                    Text(line).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                }
            }
            .padding(.vertical, skin.size.s6).padding(.leading, skin.size.s6).padding(.trailing, skin.size.s12)
            .background(
                shape.fill(
                    me
                        ? who.palette.lightColor.opacity(skin.opacity.o14)
                        : skin.color(.palette("foreground", skin.opacity.o05)))
            )
            .overlay(
                shape.strokeBorder(
                    me
                        ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o35)
                        : skin.color(.palette("foreground", skin.opacity.o07)),
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
        .agentHoverCard(store, model, who, enabled: !me)
    }
}

private struct SkillsTile: View {
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let skills = model.orgPage.agentSkills[agent.id] ?? []
        BentoBox {
            HStack {
                Text("Skills").citadelFont("t10_5", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
                Spacer()
                AinkradTapArea {
                    model.orgPage.drawer = .init(section: .skills, anchor: "library")
                } label: {
                    Text("＋ Attach").citadelFont("t11", mono: true).foregroundStyle(
                        skin.color(skin.palette.accentSecondary))
                }
                .buttonStyle(.plain)
            }
            if skills.isEmpty {
                Text("No skills reach this agent yet.").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
            }
            AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                ForEach(skills) { skill in
                    SkillChip(skill: skill) {
                        model.orgPage.selectedSkill = skill.name
                        model.orgPage.drawer = .init(section: .skills)
                    }
                }
            }
        }
    }
}

/// A cloud chip, sized by its version (prototype `--s` .85–1.21).
private struct SkillChip: View {
    let skill: SkillInfo
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let scale = 0.85 + Double(skill.version % 4) * 0.12
        let blue = skin.color(skin.palette.accentPrimary)
        let tint = scale > 1.1 ? skin.opacity.o20 : (scale > 0.95 ? skin.opacity.o12 : skin.opacity.o08)
        AinkradTapArea(action: open) {
            HStack(spacing: skin.size.s5) {
                Text(skill.name).citadelFont(
                    scale > 1.1 ? "t12_5" : scale > 0.95 ? "t12" : "t10_5", weight: "medium", mono: true
                )
                .foregroundStyle(skin.color(skin.text.primary))
                Text("v\(skill.version)").citadelFont("t9_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
            }
            .padding(.horizontal, skin.size.s10).padding(.vertical, skin.size.s5)
            .background(blue.opacity(tint), in: RoundedRectangle(cornerRadius: skin.size.s9))
            .overlay(
                RoundedRectangle(cornerRadius: skin.size.s9).strokeBorder(blue.opacity(skin.opacity.o20), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .offset(y: hovering ? -skin.size.s2 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// Now: the live log (done steps ✓, the current tool with a blinking caret) or the idle state with its queue.
private struct NowTile: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let live = model.currentRun(of: agent.id).flatMap { $0.isLive ? $0 : nil }
        if let live {
            LiveNow(store: store, model: model, agent: agent, run: live)
        } else {
            IdleNow(store: store, model: model, agent: agent)
        }
    }
}
