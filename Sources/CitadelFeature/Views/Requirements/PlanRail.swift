import AinkradAppKit
import SwiftUI

/// The requirement's live plan (`.rq-rail`): a top card with the version, a 64 pt ring, points and tasks done, ETA
/// and spend, and the burndown; then each epic as a card with its own ring that folds its tasks; and the scope
/// added since approval (no silent plan creep), which opens the plan drawer.
struct PlanRail: View {
    let store: CitadelStore
    let model: CompanyModel
    let requirement: RequirementInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @State private var diffHover = false

    private var page: RequirementsPage { model.requirementsPage }
    private var plan: PlanTree? { page.plans[requirement.id] }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s12) {
                if let plan, !plan.allTasks.isEmpty {
                    top(plan)
                    VStack(spacing: skin.size.s8) {
                        ForEach(plan.epics) { epic in
                            EpicCard(
                                store: store, model: model, requirement: requirement, title: epic.title,
                                id: epic.id, tasks: epic.tasks, started: epic.started)
                        }
                        if !plan.other.isEmpty {
                            EpicCard(
                                store: store, model: model, requirement: requirement, title: "Outside any epic",
                                id: -1, tasks: plan.other, started: true)
                        }
                    }
                    if let diff = plan.diff, let text = diff.summary {
                        AinkradTapArea(help: "Open the plan", action: { page.drawer = [.plan] }) {
                            (Text(verbatim: "\(text) · ")
                                + Text(verbatim: "diff vs v\(diff.version)").foregroundStyle(theme.accentSecondary))
                                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                                .padding(.horizontal, skin.size.s4)
                                .background(
                                    skin.color(.palette("foreground", diffHover ? skin.opacity.o08 : 0)),
                                    in: RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous))
                        }
                        .citadelHover($diffHover)  // TODO(appkit-A3)
                        .animation(skin.animation(skin.motion.hover), value: diffHover)
                    }
                } else if page.threads[requirement.id] != nil || requirement.state == "done" {
                    empty
                } else {
                    AinkradSkeletonRow(widthFraction: 0.7, showsAvatar: false).ainkradShimmer()
                    AinkradSkeletonRow(widthFraction: 0.5, showsAvatar: false).ainkradShimmer()
                }
            }
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s14)
        }
    }

    /// "No plan yet / The CEO is drafting it." or "Delivered".
    private var empty: some View {
        let done = requirement.state == "done"
        return VStack(spacing: skin.size.s8) {
            Text(done ? "✓" : "…").citadelFont("t20", weight: "semibold")
                .foregroundStyle(done ? status.success : skin.color(skin.palette.accentViolet))
                .frame(width: skin.size.s64, height: skin.size.s64)
                .background(
                    (done ? status.success : skin.color(skin.palette.accentViolet)).opacity(skin.opacity.o14),
                    in: RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous))
            Text(done ? "Delivered" : "No plan yet").citadelFont("t14", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.primary))
            Text(
                verbatim: done
                    ? "\(requirement.points) pts shipped."
                    : "The \(model.ownerWord(requirement.ownerAgentID)) is drafting it. No work starts until a plan is approved."
            )
            .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, skin.size.s48)
        .padding(.horizontal, skin.size.s10)
    }

    private func top(_ plan: PlanTree) -> some View {
        let tint = RequirementLook.tint(requirement.state, skin: skin)
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        return VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(spacing: skin.size.s8) {
                Text("Plan · live").citadelFont("t11", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.muted))
                Spacer(minLength: skin.size.s8)
                VersionBadge(requirement: requirement, plan: plan)
            }
            HStack(spacing: skin.size.s14) {
                AinkradRingGauge(
                    value: Double(plan.percent) / 100, tint: tint, diameter: skin.size.s64, lineWidth: skin.size.s6
                ) {
                    Text(verbatim: "\(plan.percent)%").citadelFont("t12", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary))
                }
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    (Text(verbatim: "\(plan.donePoints)").font(
                        skin.font(AinkradFontToken(sizeKey: "t18", weight: "bold")))
                        + Text(verbatim: "/\(plan.points) pts").font(
                            skin.font(AinkradFontToken(sizeKey: "t12", weight: "medium"))
                        )
                        .foregroundStyle(skin.color(skin.text.muted)))
                        .foregroundStyle(skin.color(skin.text.primary))
                    Text(verbatim: "\(plan.doneTasks) of \(plan.tasks) tasks done").citadelFont("t11")
                    if let eta = plan.eta {
                        Text("ETA \(Fmt.eta(eta)) · \(Fmt.dollars(micros: plan.costMicros)) so far").citadelFont("t11")
                    }
                }
                .foregroundStyle(skin.color(skin.text.faint))
            }
            if plan.eta != nil, plan.burndown.count > 1 {
                Burndown(plan: plan).frame(height: skin.size.s70)
            } else {
                Text("Burndown starts when the plan is approved.").citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.faint))
            }
        }
        .padding(skin.size.s14)
        .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o05))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
    }
}

/// "approved v1", "v1 · waiting for you", "drafting".
struct VersionBadge: View {
    let requirement: RequirementInfo
    let plan: PlanTree?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let waiting = requirement.state == "plan_review" || requirement.state == "planning"
        let tone = waiting ? status.warning : status.success
        let text =
            switch requirement.state {
            case "planning": "drafting"
            case "plan_review": "v\(max((plan?.planVersion ?? 0) + 1, 1)) · waiting for you"
            default: "approved v\(max(plan?.planVersion ?? 1, 1))"
            }
        Text(text).citadelFont("t10_5", weight: "semibold").foregroundStyle(tone)
            .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
            .background(tone.opacity(skin.opacity.o14), in: RoundedRectangle(cornerRadius: skin.size.s6))
    }
}

/// An epic as a card (`.rr-ep`): a 26 pt ring by points, the name, done/points and a chevron that folds its tasks.
private struct EpicCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let requirement: RequirementInfo
    let title: String
    let id: Int64
    let tasks: [PlanTask]
    let started: Bool
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: RequirementsPage { model.requirementsPage }

    var body: some View {
        let points = tasks.compactMap(\.points).reduce(0, +)
        let done = tasks.filter { $0.state == "done" }.compactMap(\.points).reduce(0, +)
        let shut = page.collapsedEpics.contains(id)
        let tint = started ? RequirementLook.tint(requirement.state, skin: skin) : skin.color(skin.text.faint)
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            AinkradTapArea(help: shut ? "Show tasks" : "Hide tasks", action: toggle) {
                HStack(spacing: skin.size.s10) {
                    AinkradRingGauge(
                        value: points == 0 ? 0 : Double(done) / Double(points), tint: tint, diameter: skin.size.s26,
                        lineWidth: skin.size.s3)
                    Text(title).citadelFont("t12_5", weight: "semibold").lineLimit(1)
                        .foregroundStyle(skin.color(skin.text.primary))
                    Spacer(minLength: skin.size.s6)
                    Text("\(done)/\(points)").citadelFont("t11", mono: true)
                        .foregroundStyle(skin.color(skin.text.faint))
                    Image(systemName: "chevron.down").citadelFont("t9_5", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.faint))
                        .rotationEffect(.degrees(shut ? -90 : 0))
                }
                .padding(.horizontal, skin.size.s4)
                .padding(.top, skin.size.s2)
                .padding(.bottom, skin.size.s6)
                .contentShape(Rectangle())
            }
            if !shut {
                VStack(spacing: 0) {
                    ForEach(tasks) { task in RailTaskRow(store: store, model: model, task: task) }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .padding(skin.size.s8)
        .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o03))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o06)), lineWidth: 1))
        .clipShape(shape)
    }

    private func toggle() {
        withAnimation(reduceMotion ? nil : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.25))) {
            if page.collapsedEpics.contains(id) {
                page.collapsedEpics.remove(id)
            } else {
                page.collapsedEpics.insert(id)
            }
        }
    }
}

/// A task (`.rr-tk`): glyph tile, key and title, a mono meta line, the assignee and a points pill. Amber when it
/// asks you. Opens the assignee's thread on it (the work-item drawer is Projects' shared panel).
private struct RailTaskRow: View {
    let store: CitadelStore
    let model: CompanyModel
    let task: PlanTask
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let glyph = model.glyph(task)
        AinkradTapArea(help: "\(task.key) · \(task.state.replacingOccurrences(of: "_", with: " "))", action: open) {
            HStack(spacing: skin.size.s8) {
                Text(glyph.glyph).citadelFont("t10").foregroundStyle(glyph.tone.tint(skin))
                    .frame(width: skin.size.s20, height: skin.size.s20)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o05)),
                        in: RoundedRectangle(cornerRadius: skin.size.s6)
                    )
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: glyph)
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    HStack(alignment: .firstTextBaseline, spacing: skin.size.s6) {
                        Text(task.key).citadelFont("t10", mono: true).foregroundStyle(theme.accentSecondary)
                        Text(task.title).citadelFont("t12", weight: "medium").lineLimit(1)
                            .foregroundStyle(skin.color(skin.text.primary))
                    }
                    if let meta = model.taskMeta(task) {
                        Text(meta).citadelFont("t10", mono: true).foregroundStyle(skin.color(skin.text.faint))
                            .lineLimit(1)
                    }
                }
                Spacer(minLength: skin.size.s4)
                if let agent = model.agent(task.assigneeAgentID) {
                    AgentFigure(agent: agent, model: model, size: skin.size.s20)
                }
                PointsPill(points: task.points)
            }
            .padding(skin.size.s6)
            .background(
                RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous).fill(
                    glyph == .waiting
                        ? status.warning.opacity(skin.opacity.o12)
                        : skin.color(.palette("foreground", hovering ? skin.opacity.o06 : 0)))
            )
            .contentShape(Rectangle())
        }
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }

    private func open() { model.requirementsPage.openItem(task.issueID) }
}

/// The points pill (`.qc-pts`): mono 10/600 on a soft tile.
struct PointsPill: View {
    let points: Int?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(points.map(String.init) ?? "–").citadelFont("t10", weight: "semibold", mono: true)
            .foregroundStyle(skin.color(skin.text.primary))
            .frame(minWidth: skin.size.s20)
            .padding(.horizontal, skin.size.s3)
            .padding(.vertical, skin.size.s2)
            .background(
                skin.color(.palette("foreground", skin.opacity.o08)), in: RoundedRectangle(cornerRadius: skin.size.s5))
    }
}
