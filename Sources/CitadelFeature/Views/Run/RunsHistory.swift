import AinkradAppKit
import SwiftUI

/// The history: day groups (`Today · 7 runs · $7.65`), each a glass list of rows.
struct RunsHistory: View {
    let store: CitadelStore
    let model: CompanyModel
    let runs: [RunInfo]
    let now: Date
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let longest = max(runs.map { model.elapsed($0, now: now) }.max() ?? 1, 1)
        VStack(alignment: .leading, spacing: skin.size.s14) {
            ForEach(RunDay.groups(runs, now: now), id: \.title) { group in
                VStack(alignment: .leading, spacing: skin.size.s6) {
                    HStack(alignment: .firstTextBaseline, spacing: skin.size.s10) {
                        Text(group.title).citadelFont("t12_5", weight: "bold")
                            .foregroundStyle(skin.color(skin.text.primary))
                        Text(dayLine(group.runs)).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    }
                    .padding(.horizontal, skin.size.s4)
                    VStack(spacing: skin.size.s2) {
                        ForEach(group.runs) { run in
                            RunsHistoryRow(
                                store: store, model: model, run: run, longest: longest,
                                isOpen: model.runsPage.peekID == run.id)
                        }
                    }
                    .padding(skin.size.s5)
                    .background(
                        RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
                            .fill(skin.color(.palette("background", skin.opacity.o55)))
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
                            .strokeBorder(skin.color(.palette("foreground", skin.opacity.o05)), lineWidth: 1))
                }
            }
        }
    }

    /// "7 runs · $7.65".
    private func dayLine(_ runs: [RunInfo]) -> String {
        "\(Wording.count(runs.count, "run")) · \(Fmt.dollars(micros: runs.compactMap(\.costMicros).reduce(0, +)))"
    }
}

/// `.rs-row`: outcome tile · #id · orb + key/title over "Agent · state · ended HH:MM" · duration bar · duration ·
/// tokens · cost (never $0) · a chevron that shows on hover.
struct RunsHistoryRow: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    let longest: TimeInterval
    let isOpen: Bool
    @State private var hovering = false
    @State private var grown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let look = model.look(run)
        let tint = Hue(look.tone).color(skin)
        let agent = model.agent(run.agentID)
        let issue = model.issue(run.issueID)
        let elapsed = model.elapsed(run)
        AinkradTapArea(action: { store.peek(run: run.id) }) {
            HStack(spacing: skin.size.s12) {
                Text(look.glyph).citadelFont("t12", weight: "bold").foregroundStyle(tint)
                    .frame(width: skin.size.s28, height: skin.size.s28)
                    .background(tint.opacity(skin.opacity.o16), in: RoundedRectangle(cornerRadius: skin.size.s8))
                    .frame(width: skin.size.s30)
                Text("#\(run.id)").citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    .frame(width: skin.size.s44, alignment: .leading)
                HStack(spacing: skin.size.s9) {
                    if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s24) }
                    VStack(alignment: .leading, spacing: skin.size.s1) {
                        (Text(issue.map { "\($0.key) " } ?? "")
                            .font(skin.font(AinkradFontToken(sizeKey: "t12", weight: "semibold", mono: "family")))
                            .foregroundStyle(skin.color(skin.palette.accentSecondary))
                            + Text(issue?.title ?? model.runTitle(run)).foregroundStyle(skin.color(skin.text.primary)))
                            .citadelFont("t13", weight: "medium").lineLimit(1)
                        Text(subtitle(look, agent: agent)).citadelFont("t11").foregroundStyle(
                            skin.color(skin.text.faint)
                        )
                        .lineLimit(1)
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                durationBar(tint, fraction: max(0.04, elapsed / longest))
                    .frame(minWidth: skin.size.s90, maxWidth: skin.size.s160)
                number(RunLook.span(elapsed))
                number(Fmt.tokens(run.tokens))
                cost.frame(width: skin.size.s80, alignment: .trailing)
                Text("›").citadelFont("t13").foregroundStyle(skin.color(skin.text.faint))
                    .frame(width: skin.size.s14)
                    .opacity(hovering ? 1 : 0)
                    .offset(x: hovering || reduceMotion ? 0 : -skin.size.s4)
            }
            .padding(.horizontal, skin.size.s10)
            .padding(.vertical, skin.size.s7)
            .background(
                skin.color(.palette("foreground", hovering || isOpen ? skin.opacity.o05 : 0)),
                in: RoundedRectangle(cornerRadius: skin.size.s11, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: hovering)
        .onAppear { grown = true }
    }

    /// "Rook · runner lost · ended 09:58".
    private func subtitle(_ look: RunLook, agent: AgentInfo?) -> String {
        var parts = [agent?.name ?? "Agent", look.word]
        if let ended = run.endedAt, Calendar.current.isDateInToday(ended) {
            parts.append("ended \(ended.formatted(date: .omitted, time: .shortened))")
        }
        return parts.joined(separator: " · ")
    }

    private func durationBar(_ tint: Color, fraction: Double) -> some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(skin.color(.palette("foreground", skin.opacity.o06)))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(skin.opacity.o50), tint], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * min(1, fraction))
                    .scaleEffect(x: grown || reduceMotion ? 1 : 0, anchor: .leading)
                    .animation(skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.6)), value: grown)
            }
        }
        .frame(height: skin.size.s6)
    }

    private func number(_ text: String) -> some View {
        Text(text).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.muted))
            .frame(width: skin.size.s56, alignment: .trailing).lineLimit(1)
    }

    @ViewBuilder private var cost: some View {
        let cost = model.cost(run)
        switch cost {
        case .priced: Text(cost.word).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.muted))
        case .subscription: Text(cost.word).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        case .unpriced: Text(cost.word).citadelFont("t11").foregroundStyle(skin.color(skin.palette.warning))
        }
    }
}

/// A project's gradient tile with its initial (`rsProjTile`), in a colour pair picked from its key.
struct ProjectTile: View {
    let project: ProjectInfo
    var size: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let side = size ?? skin.size.s30
        let palettes = AinkradFigurePalette.all
        let palette = palettes[abs(project.key.unicodeScalars.reduce(0) { $0 &+ Int($1.value) }) % palettes.count]
        Text(String(project.name.prefix(1))).citadelFont("t13", weight: "bold")
            .foregroundStyle(skin.color(.palette("foreground", 1)))
            .frame(width: side, height: side)
            .background(
                LinearGradient(
                    colors: [palette.lightColor, palette.deepColor], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous))
    }
}

/// "Agent · Everyone": filter the runs by agent.
struct RunsAgentPicker: View {
    let model: CompanyModel
    let page: RunsPage
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let runs = model.knownRuns
        let ids = Array(Set(runs.map(\.agentID))).sorted {
            (model.agent($0)?.name ?? "") < (model.agent($1)?.name ?? "")
        }
        let selected = model.agent(page.agentID)
        AinkradRichPicker(
            caption: "Agent", value: selected?.name ?? "Everyone", isOn: selected != nil,
            isOpen: Binding(get: { page.openPicker == "agent" }, set: { page.openPicker = $0 ? "agent" : nil })
        ) {
            if let selected {
                AgentFigure(agent: selected, model: model, size: skin.size.s30)
            } else {
                Image(systemName: "person.2").citadelFont("t14")
            }
        } menu: {
            AinkradRichMenu(header: "Filter runs by agent") {
                AinkradRichMenuRow(
                    title: "Everyone",
                    subtitle: "\(Wording.count(ids.count, "agent")) · \(Wording.count(runs.count, "run"))",
                    isChecked: page.agentID == nil, action: { pick(nil) }
                ) { RunAvatarStack(model: model, ids: Array(ids.prefix(4))) }
                AinkradRichMenuSeparator()
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    if let agent = model.agent(id) {
                        AinkradRichMenuRow(
                            title: agent.name, subtitle: "\(agent.role) · \(agent.harnessName)",
                            count: runs.filter { $0.agentID == id }.count, isChecked: page.agentID == id,
                            index: index + 1, action: { pick(id) }
                        ) {
                            AgentFigure(agent: agent, model: model, size: skin.size.s28)
                        } extra: {
                            if model.liveRuns.contains(where: { $0.agentID == id }) { LiveChip() }
                        }
                    }
                }
            }
        }
    }

    private func pick(_ id: Int64?) {
        page.agentID = id
        page.openPicker = nil
    }
}

/// "Project · All projects": filter the runs by their issue's project.
struct RunsProjectPicker: View {
    let model: CompanyModel
    let page: RunsPage
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let runs = model.knownRuns
        let selected = model.projects.first { $0.id == page.projectID }
        AinkradRichPicker(
            caption: "Project", value: selected?.name ?? "All projects", isOn: selected != nil,
            isOpen: Binding(get: { page.openPicker == "project" }, set: { page.openPicker = $0 ? "project" : nil })
        ) {
            if let selected {
                ProjectTile(project: selected)
            } else {
                Image(systemName: "square.stack").citadelFont("t14")
            }
        } menu: {
            AinkradRichMenu(header: "Filter runs by project") {
                AinkradRichMenuRow(
                    title: "All projects", subtitle: Wording.count(model.projects.count, "project"), count: runs.count,
                    isChecked: page.projectID == nil, action: { pick(nil) }
                ) {
                    Image(systemName: "square.stack").citadelFont("t13").foregroundStyle(skin.color(skin.text.muted))
                        .frame(width: skin.size.s30, height: skin.size.s30)
                        .background(
                            skin.color(.palette("foreground", skin.opacity.o08)),
                            in: RoundedRectangle(cornerRadius: skin.size.s9))
                }
                AinkradRichMenuSeparator()
                ForEach(Array(model.projects.enumerated()), id: \.element.id) { index, project in
                    let mine = runs.filter { model.issue($0.issueID)?.projectID == project.id }
                    let ok = mine.filter { model.look($0).tab == .succeeded }.count
                    let bad = mine.filter { model.look($0).tab == .failed }.count
                    AinkradRichMenuRow(
                        title: project.name, subtitle: "\(project.key) · \(ok) ok\(bad > 0 ? " · \(bad) failed" : "")",
                        count: mine.count, isChecked: page.projectID == project.id, index: index + 1,
                        action: { pick(project.id) }
                    ) {
                        ProjectTile(project: project)
                    } extra: {
                        OutcomeSpark(ok: ok, bad: bad, live: mine.count - ok - bad)
                    }
                }
            }
        }
    }

    private func pick(_ id: Int64?) {
        page.projectID = id
        page.openPicker = nil
    }
}

/// Up to four agent orbs overlapping (`.rm-stack`).
struct RunAvatarStack: View {
    let model: CompanyModel
    let ids: [Int64]
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: -skin.size.s10) {
            ForEach(ids, id: \.self) { id in
                if let agent = model.agent(id) {
                    AgentFigure(agent: agent, model: model, size: skin.size.s22)
                        .background(Circle().fill(skin.color(.palette("surface", 1))).padding(-skin.size.s2))
                }
            }
        }
        .frame(width: skin.size.s56, alignment: .leading)
    }
}

/// `● live` in cyan, the dot glowing.
struct LiveChip: View {
    @Environment(\.ainkradSkin) private var skin
    var body: some View {
        let cyan = skin.color(skin.palette.accentSecondary)
        HStack(spacing: skin.size.s5) {
            Circle().fill(cyan).frame(width: skin.size.s6, height: skin.size.s6).shadow(
                color: cyan, radius: skin.size.s4)
            Text("live").citadelFont("t10_5")
        }
        .foregroundStyle(cyan)
    }
}

/// `.rm-spark`: a 54×6 split of ok, failed and still-running runs.
struct OutcomeSpark: View {
    let ok: Int
    let bad: Int
    let live: Int
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let total = Double(max(ok + bad + live, 1))
        GeometryReader { geo in
            HStack(spacing: skin.size.s1) {
                Rectangle().fill(skin.color(skin.palette.success)).frame(width: geo.size.width * Double(ok) / total)
                Rectangle().fill(skin.color(skin.palette.danger)).frame(width: geo.size.width * Double(bad) / total)
                Rectangle().fill(skin.color(.palette("foreground", skin.opacity.o15)))
            }
        }
        .frame(width: skin.size.s54, height: skin.size.s6)
        .background(skin.color(.palette("foreground", skin.opacity.o06)))
        .clipShape(Capsule())
    }
}
