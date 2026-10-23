import AinkradAppKit
import SwiftUI

/// The requirement's live plan: % done by points, task count, burndown vs ideal, ETA, tokens and dollars so far,
/// and the tree — epic → task with its state glyph, assignee, points. The task asking you is amber; scope added
/// after approval is called out (no silent plan creep).
struct PlanRail: View {
    let store: CitadelStore
    let model: CompanyModel
    let requirement: RequirementInfo
    @State private var showsDiff = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var plan: PlanTree? { model.requirementsPage.plans[requirement.id] }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(spacing: skin.size.s8) {
                Text(skin.labelCased("Plan · live")).citadelFont("t10", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.muted))
                Spacer(minLength: skin.size.s8)
                versionBadge
            }
            if let plan {
                summary(plan)
                ScrollView {
                    VStack(alignment: .leading, spacing: skin.size.s2) {
                        ForEach(plan.epics) { epic in
                            epicRow(epic)
                            ForEach(epic.tasks) { task in TaskRow(store: store, model: model, task: task) }
                        }
                        if !plan.other.isEmpty {
                            epicHead(glyph: "◇", title: "Outside any epic", count: nil, started: false)
                            ForEach(plan.other) { task in TaskRow(store: store, model: model, task: task) }
                        }
                    }
                }
                if let diff = plan.diff, let text = diff.summary { diffLine(diff, text) }
            } else {
                AinkradSkeletonRow(widthFraction: 0.7, showsAvatar: false)
                AinkradSkeletonRow(widthFraction: 0.5, showsAvatar: false)
                Spacer(minLength: 0)
            }
        }
        .padding(skin.size.s16)
        .frame(maxHeight: .infinity, alignment: .top)
    }

    @ViewBuilder private var versionBadge: some View {
        switch requirement.state {
        case "planning": AinkradBadge(text: "drafting")
        case "plan_review": AinkradBadge(text: "plan to approve", status: .warning)
        default: AinkradBadge(text: "approved v\(max(plan?.planVersion ?? 1, 1))", status: .success)
        }
    }

    private func summary(_ plan: PlanTree) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s8) {
            HStack(alignment: .firstTextBaseline, spacing: skin.size.s6) {
                Text("\(plan.percent)%").citadelFont("t24", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.primary))
                    .contentTransition(.numericText(value: Double(plan.percent)))
                Text("\(plan.donePoints) of \(plan.points) pts · \(plan.doneTasks) of \(plan.tasks) done")
                    .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
            }
            .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: plan.percent)
            AinkradBudgetBar(
                label: "\(requirement.key) progress", value: Double(plan.donePoints),
                limit: Double(max(plan.points, 1)), warnFraction: nil, showsHardLimit: false, isThick: true)
            AinkradLineChart(
                title: "Burndown", series: Self.burndown(plan), axisLabels: Self.axis(plan), emptyMessage: "",
                format: { "\(Int($0)) pts left" }
            )
            .frame(height: skin.size.s48)
            Text(Self.facts(plan)).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
        }
    }

    /// The actual line and the ideal one (from the first day's points to zero at the ETA).
    static func burndown(_ plan: PlanTree) -> [AinkradChartSeries] {
        let actual = plan.burndown.enumerated().map {
            AinkradChartPoint(x: Double($0.offset), y: Double($0.element.left))
        }
        guard let start = plan.burndown.first?.left else { return [] }
        let days =
            Double(max(plan.burndown.count - 1, 0)) + Double(plan.burndown.last?.left ?? 0)
            / max(plan.pointsPerDay, 0.1)
        return [
            AinkradChartSeries(
                name: "Ideal", points: [AinkradChartPoint(x: 0, y: Double(start)), AinkradChartPoint(x: days, y: 0)],
                tone: .muted, isDashed: true),
            AinkradChartSeries(name: "Left", points: actual, tone: .accentSecondary),
        ]
    }

    private static func axis(_ plan: PlanTree) -> [AinkradChartAxisLabel] {
        guard let first = plan.burndown.first else { return [] }
        var labels = [AinkradChartAxisLabel(x: 0, text: Fmt.eta(first.day))]
        if let eta = plan.eta, let end = burndown(plan).first?.points.last?.x {
            labels.append(AinkradChartAxisLabel(x: end, text: Fmt.eta(eta)))
        }
        return labels
    }

    /// "2 in review · ETA Tue · 312k tok · $14.20 so far".
    static func facts(_ plan: PlanTree) -> String {
        var parts: [String] = []
        if plan.inReview > 0 { parts.append("\(plan.inReview) in review") }
        if let eta = plan.eta { parts.append("ETA \(Fmt.eta(eta))") }
        parts.append("\(Fmt.tokens(plan.tokens)) tok")
        parts.append("\(Fmt.dollars(micros: plan.costMicros)) so far")
        return parts.joined(separator: " · ")
    }

    private func epicRow(_ epic: PlanEpic) -> some View {
        epicHead(
            glyph: epic.started ? "◆" : "◇", title: epic.key.map { "\($0) · \(epic.title)" } ?? epic.title,
            count: "\(epic.donePoints) / \(epic.points)",
            started: epic.started)
    }

    private func epicHead(glyph: String, title: String, count: String?, started: Bool) -> some View {
        HStack(spacing: skin.size.s8) {
            Text(glyph).citadelFont("t12").foregroundStyle(
                started ? theme.accentSecondary : skin.color(skin.text.faint))
            Text(title).citadelFont("t12_5", weight: "semibold").lineLimit(1)
                .foregroundStyle(skin.color(skin.text.primary))
            Spacer(minLength: skin.size.s6)
            if let count {
                Text(count).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.muted))
            }
        }
        .padding(.horizontal, skin.size.s4)
        .padding(.top, skin.size.s8)
        .padding(.bottom, skin.size.s4)
    }

    private func diffLine(_ diff: PlanDiffInfo, _ text: String) -> some View {
        HStack(spacing: skin.size.s4) {
            Text("\(text) ·").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(2)
            AinkradButton(title: "diff vs v\(diff.version)", style: .ghost) { showsDiff = true }
                .borderless().secondaryAccent().compact().fixedSize()
                .ainkradPopover(isPresented: $showsDiff) { diffDetail(diff) }
        }
    }

    private func diffDetail(_ diff: PlanDiffInfo) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            Text("Since v\(diff.version) · \(diff.pointsApproved) → \(diff.pointsNow) pts").citadelFont(
                "t12", weight: "semibold")
            ForEach(diff.added.map(\.key), id: \.self) { Text("+ \($0)").citadelFont("t11", mono: true) }
            ForEach(diff.removed.map(\.key), id: \.self) { Text("− \($0)").citadelFont("t11", mono: true) }
        }
        .padding(skin.size.s12)
    }
}

/// A task: glyph, key, title, assignee, points, and its faint second line. Amber when it asks you; clicking opens
/// the assignee's thread on it.
private struct TaskRow: View {
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
        VStack(alignment: .leading, spacing: skin.size.s1) {
            HStack(spacing: skin.size.s6) {
                Text(glyph.glyph).citadelFont("t11").foregroundStyle(glyph.tone.tint(skin))
                    .frame(width: skin.size.s14).contentTransition(.opacity)
                    .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: glyph)
                Text(task.key).citadelFont("t10", mono: true).foregroundStyle(theme.accentSecondary)
                    .frame(width: skin.size.s50, alignment: .leading)
                Text(task.title).citadelFont("t11").lineLimit(1).foregroundStyle(skin.color(skin.text.primary))
                Spacer(minLength: skin.size.s4)
                if let agent = model.agent(task.assigneeAgentID) {
                    AgentFigure(agent: agent, model: model, size: skin.size.s18)
                }
                Text(task.points.map(String.init) ?? "?").citadelFont("t10", mono: true)
                    .frame(width: skin.size.s18)
                    .background(
                        skin.color(skin.palette.white).opacity(skin.opacity.o07),
                        in: RoundedRectangle(cornerRadius: skin.size.s3))
            }
            if let meta = model.taskMeta(task) {
                Text(meta).citadelFont("t10", mono: true).foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    .padding(.leading, skin.size.s70)
            }
        }
        .padding(.horizontal, skin.size.s6)
        .padding(.vertical, skin.size.s4)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous).fill(
                glyph == .waiting
                    ? status.warning.opacity(skin.opacity.o10)
                    : skin.color(skin.palette.white).opacity(hovering ? skin.opacity.o05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture {
            guard let agent = task.assigneeAgentID else { return }
            store.selectedThread = ThreadKey(agentID: agent, issueID: task.issueID)
            store.screen = .threads
        }
        .help("\(task.key) · \(task.state.replacingOccurrences(of: "_", with: " "))")
        .accessibilityElement(children: .combine)
    }
}
