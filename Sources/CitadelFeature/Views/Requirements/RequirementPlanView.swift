import AinkradAppKit
import SwiftUI

/// The plan in the drawer (`reqPlanView`): the head card (76 pt ring, version, ETA, points / tasks / epics / spent),
/// the status bar by task state with its legend, the burndown, who is on the plan, every epic with its tasks, and
/// what changed since approval.
struct RequirementPlanView: View {
    let store: CitadelStore
    let model: CompanyModel
    let requirement: RequirementInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    private var plan: PlanTree? { model.requirementsPage.plans[requirement.id] }

    var body: some View {
        if let plan {
            VStack(alignment: .leading, spacing: skin.size.s14) {
                head(plan)
                statusBar(plan)
                if plan.eta != nil, plan.burndown.count > 1 { burn(plan) }
                people(plan)
                ForEach(Array(plan.epics.enumerated()), id: \.element.id) { index, epic in
                    epicSection(epic, color: Self.epicColor(index, skin: skin))
                }
                if let diff = plan.diff, let text = diff.summary {
                    HStack(spacing: skin.size.s12) {
                        Text("±").citadelFont("t12").foregroundStyle(status.warning)
                            .frame(width: skin.size.s30, height: skin.size.s30)
                            .background(
                                status.warning.opacity(skin.opacity.o16),
                                in: RoundedRectangle(cornerRadius: skin.size.s9))
                        VStack(alignment: .leading, spacing: skin.size.s1) {
                            Text("Changed since approval").citadelFont("t12", weight: "semibold")
                                .foregroundStyle(skin.color(skin.text.primary))
                            Text(text).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                        }
                    }
                    .padding(skin.size.s12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        status.warning.opacity(skin.opacity.o06), in: RoundedRectangle(cornerRadius: skin.size.s14)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: skin.size.s14).strokeBorder(
                            status.warning.opacity(skin.opacity.o25), lineWidth: 1))
                }
            }
        } else {
            AinkradEmptyState(
                icon: "ellipsis", title: "No plan yet",
                message: "The \(model.ownerWord(requirement.ownerAgentID)) is drafting it."
            )
            .padding(.vertical, skin.size.s60)
        }
    }

    /// `EPIC_COL`: cyan, violet, amber, green, pink.
    static func epicColor(_ index: Int, skin: AinkradSkin) -> Color {
        let colors = [
            skin.color(skin.palette.accentSecondary), skin.color(skin.palette.accentViolet),
            skin.color(skin.palette.warning), skin.color(skin.palette.success),
            AinkradFigurePalette.orchid.lightColor,
        ]
        return colors[index % colors.count]
    }

    private func head(_ plan: PlanTree) -> some View {
        let tint = RequirementLook.tint(requirement.state, skin: skin)
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        let kpis: [(String, String?, String)] = [
            ("\(plan.donePoints)", "/\(plan.points)", "points"), ("\(plan.doneTasks)", "/\(plan.tasks)", "tasks"),
            ("\(plan.epics.count)", nil, "epics"), (Fmt.dollars(micros: plan.costMicros), nil, "spent"),
        ]
        return HStack(spacing: skin.size.s16) {
            AinkradRingGauge(
                value: Double(plan.percent) / 100, tint: tint, diameter: skin.size.s72 + skin.size.s4,
                lineWidth: skin.size.s7
            ) {
                Text(verbatim: "\(plan.percent)%").citadelFont("t14", weight: "semibold", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary))
            }
            VStack(alignment: .leading, spacing: skin.size.s8) {
                HStack(alignment: .firstTextBaseline, spacing: skin.size.s8) {
                    Text(requirement.key).citadelFont("t12", mono: true).foregroundStyle(theme.accentSecondary)
                    Text(requirement.title).citadelFont("t16", weight: "bold").lineLimit(1)
                        .foregroundStyle(skin.color(skin.text.primary))
                }
                HStack(spacing: skin.size.s10) {
                    VersionBadge(requirement: requirement, plan: plan)
                    if let eta = plan.eta {
                        Text("ETA \(Fmt.eta(eta))").citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                    }
                }
                HStack(spacing: skin.size.s6) {
                    ForEach(kpis, id: \.2) { value, of, label in
                        VStack(alignment: .leading, spacing: 0) {
                            (Text(value).font(skin.font(AinkradFontToken(sizeKey: "t16", weight: "bold")))
                                + Text(of ?? "").font(skin.font(AinkradFontToken(sizeKey: "t11", weight: "medium")))
                                .foregroundStyle(skin.color(skin.text.muted)))
                                .foregroundStyle(skin.color(skin.text.primary))
                            Text(label).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                        }
                        .padding(.horizontal, skin.size.s10)
                        .padding(.vertical, skin.size.s8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(
                            skin.color(.palette("black", skin.opacity.o20)),
                            in: RoundedRectangle(cornerRadius: skin.size.s10))
                    }
                }
            }
        }
        .padding(skin.size.s16)
        .background(
            shape.fill(
                LinearGradient(
                    colors: [tint.opacity(skin.opacity.o12), skin.color(.palette("foreground", skin.opacity.o03))],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o30), lineWidth: 1))
    }

    private static let order: [TaskGlyph] = [.done, .running, .review, .waiting, .blocked, .todo]

    private func label(_ glyph: TaskGlyph) -> String {
        switch glyph {
        case .done: "Done"
        case .running: "Running"
        case .review: "In review"
        case .waiting: "Waiting"
        case .blocked: "Blocked"
        case .todo: "To do"
        }
    }

    private func glyphColor(_ glyph: TaskGlyph) -> Color {
        glyph == .review ? skin.color(skin.palette.accentViolet) : glyph.tone.tint(skin)
    }

    private func statusBar(_ plan: PlanTree) -> some View {
        let groups = Self.order.map { glyph in (glyph, plan.allTasks.filter { model.glyph($0) == glyph }.count) }
            .filter { $0.1 > 0 }
        return VStack(alignment: .leading, spacing: skin.size.s8) {
            GeometryReader { geo in
                HStack(spacing: skin.size.s3) {
                    ForEach(groups, id: \.0) { glyph, count in
                        glyphColor(glyph).frame(
                            width: max(
                                0,
                                (geo.size.width - skin.size.s3 * Double(groups.count - 1)) * Double(count)
                                    / Double(max(plan.allTasks.count, 1))))
                    }
                }
            }
            .frame(height: skin.size.s12)
            .clipShape(RoundedRectangle(cornerRadius: skin.size.s6))
            AinkradFlowLayout(spacing: skin.size.s14) {
                ForEach(groups, id: \.0) { glyph, count in
                    HStack(spacing: skin.size.s6) {
                        RoundedRectangle(cornerRadius: skin.size.s2).fill(glyphColor(glyph))
                            .frame(width: skin.size.s8, height: skin.size.s8)
                        Text(verbatim: "\(label(glyph)) \(count)").citadelFont("t11").foregroundStyle(
                            skin.color(skin.text.muted))
                    }
                }
            }
        }
    }

    private func burn(_ plan: PlanTree) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s8) {
            HStack {
                Text("Burndown").citadelFont("t11", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
                Spacer()
                Text(verbatim: "\(plan.points - plan.donePoints) pts left").citadelFont("t11", mono: true)
                    .foregroundStyle(skin.color(skin.text.faint))
            }
            Burndown(plan: plan).frame(height: skin.size.s90)
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.vertical, skin.size.s12)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)), in: RoundedRectangle(cornerRadius: skin.size.s14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s14).strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o06)), lineWidth: 1))
    }

    private func people(_ plan: PlanTree) -> some View {
        var ids: [Int64] = []
        for id in plan.allTasks.compactMap(\.assigneeAgentID) where !ids.contains(id) { ids.append(id) }
        return AinkradFlowLayout(spacing: skin.size.s6) {
            Text("On this plan").citadelFont("t11", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
                .frame(height: skin.size.s32)
            ForEach(ids.compactMap { model.agent($0) }) { agent in
                ThreadHeroChip(action: { store.open(.agent(agent.id)) }) {
                    AgentFigure(agent: agent, model: model, size: skin.size.s22)
                    Text(agent.name).citadelFont("t12", weight: "semibold")
                    PointsPill(points: plan.allTasks.filter { $0.assigneeAgentID == agent.id }.count)
                }
            }
        }
    }

    private func epicSection(_ epic: PlanEpic, color: Color) -> some View {
        let done = epic.tasks.filter { $0.state == "done" }.compactMap(\.points).reduce(0, +)
        let points = epic.tasks.compactMap(\.points).reduce(0, +)
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        return VStack(alignment: .leading, spacing: skin.size.s4) {
            HStack(spacing: skin.size.s10) {
                Text("◆").citadelFont("t12").foregroundStyle(color)
                    .frame(width: skin.size.s30, height: skin.size.s30)
                    .background(color.opacity(skin.opacity.o16), in: RoundedRectangle(cornerRadius: skin.size.s9))
                VStack(alignment: .leading, spacing: 0) {
                    Text(epic.title).citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                    Text(verbatim: "\(Wording.count(epic.tasks.count, "task")) · \(points) pts").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                }
                Spacer(minLength: skin.size.s8)
                ProgressLine(value: points == 0 ? 0 : Double(done) / Double(points), tint: color)
                    .frame(width: skin.size.s120)
                Text(verbatim: "\(done)/\(points)").citadelFont("t11", mono: true).foregroundStyle(
                    skin.color(skin.text.muted))
            }
            .padding(.horizontal, skin.size.s4)
            .padding(.bottom, skin.size.s6)
            ForEach(epic.tasks) { task in
                PlanTaskRow(store: store, model: model, task: task, color: glyphColor(model.glyph(task)))
            }
        }
        .padding(skin.size.s12)
        .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o03))))
        .overlay(alignment: .leading) { Rectangle().fill(color).frame(width: skin.size.s3) }
        .clipShape(shape)
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
    }
}

/// A task in the drawer's plan (`.pv-tk`): glyph tile 26, key + title, state · meta, the assignee and points; a ›
/// slides in on hover.
private struct PlanTaskRow: View {
    let store: CitadelStore
    let model: CompanyModel
    let task: PlanTask
    let color: Color
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let glyph = model.glyph(task)
        let agent = model.agent(task.assigneeAgentID)
        AinkradTapArea(action: open) {
            HStack(spacing: skin.size.s10) {
                Text(glyph.glyph).citadelFont("t11").foregroundStyle(color)
                    .frame(width: skin.size.s26, height: skin.size.s26)
                    .background(color.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s8))
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    HStack(alignment: .firstTextBaseline, spacing: skin.size.s6) {
                        Text(task.key).citadelFont("t11", mono: true).foregroundStyle(theme.accentSecondary)
                        Text(task.title).citadelFont("t12_5", weight: "medium").lineLimit(1)
                            .foregroundStyle(skin.color(skin.text.primary))
                    }
                    Text(stateLine(glyph)).citadelFont("t10_5").lineLimit(1)
                        .foregroundStyle([.waiting, .blocked].contains(glyph) ? color : skin.color(skin.text.faint))
                }
                Spacer(minLength: skin.size.s6)
                HStack(spacing: skin.size.s6) {
                    if let agent {
                        AgentFigure(agent: agent, model: model, size: skin.size.s22)
                        Text(agent.name).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
                    }
                }
                .frame(width: skin.size.s92, alignment: .leading)
                PointsPill(points: task.points)
                Text("›").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                    .opacity(hovering ? 1 : 0).offset(x: hovering || reduceMotion ? 0 : -skin.size.s4)
            }
            .padding(skin.size.s8)
            .background(
                skin.color(.palette("foreground", hovering ? skin.opacity.o06 : 0)),
                in: RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .offset(x: hovering && !reduceMotion ? skin.size.s3 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }

    private func stateLine(_ glyph: TaskGlyph) -> String {
        let word: String =
            switch glyph {
            case .done: "Done"
            case .running: "Running"
            case .review: "In review"
            case .waiting: "Waiting on you"
            case .blocked: "Blocked"
            case .todo: "To do"
            }
        guard let meta = model.taskMeta(task) else { return word }
        let rest = meta.replacingOccurrences(
            of: "^(done|blocked|asks you)( · )?", with: "", options: .regularExpression
        )
        .replacingOccurrences(of: "( · )?in review$", with: "", options: .regularExpression)
        return rest.isEmpty ? word : "\(word) · \(rest)"
    }

    private func open() { model.requirementsPage.openItem(task.issueID) }
}

/// One artifact, full size (`reqArtView`): its type tile, name and meta, Run ⇱ and issue links, the big preview, and
/// the foot — Download, Open in Artifacts.
struct ArtifactPreview: View {
    let store: CitadelStore
    let model: CompanyModel
    let requirement: RequirementInfo
    let id: Int64
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        if let artifact = model.requirementArtifacts(requirement).first(where: { $0.id == id }) {
            VStack(alignment: .leading, spacing: skin.size.s14) {
                HStack(spacing: skin.size.s12) {
                    ArtifactTypeTile(artifact: artifact, size: skin.size.s40)
                    VStack(alignment: .leading, spacing: skin.size.s1) {
                        Text(artifact.name).citadelFont("t14", weight: "semibold")
                            .foregroundStyle(skin.color(skin.text.primary))
                        Text("\(model.artifactMeta(artifact, sized: true)) · \(model.artifactByline(artifact))")
                            .citadelFont("t11")
                            .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    }
                    Spacer(minLength: skin.size.s8)
                    if let run = artifact.runID {
                        AinkradButton(title: "Run #\(run) ⇱", style: .ghost) {
                            model.requirementsPage.drawer = []
                            store.open(.run(run))
                        }
                        .borderless().secondaryAccent().compact().fixedSize()
                    }
                }
                ArtifactBody(model: model, artifact: artifact)
                    .frame(minHeight: skin.size.s320, maxHeight: artifact.isImage ? skin.size.s400 : nil)
                    .frame(maxWidth: .infinity)
                    .background(
                        skin.color(.palette("black", skin.opacity.o28)),
                        in: RoundedRectangle(cornerRadius: skin.size.s16)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: skin.size.s16))
                HStack(spacing: skin.size.s8) {
                    Text(artifact.isImage ? "Space for full size" : "Read-only · versioned with the run")
                        .citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                    Spacer(minLength: skin.size.s8)
                    AinkradButton(title: "Download", style: .secondary) { store.download(artifact) }.compact()
                        .fixedSize()
                    AinkradButton(title: "Open in Artifacts", style: .secondary) {
                        model.requirementsPage.drawer = []
                        model.artifactsPage.selectedID = artifact.id
                        store.showArtifacts(requirement: requirement.id)
                    }
                    .compact().fixedSize()
                }
            }
            .onAppear { store.loadPreview(artifact) }
        }
    }
}
