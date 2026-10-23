import AinkradAppKit
import SwiftUI

/// Screen 02: what needs me first — account warning, four tiles, open requirements, live runs, then the merged
/// "needs you" list beside spend. Everything is pushed by the event stream.
struct HomeView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @State private var pageWidth: CGFloat = 0
    @State private var confirmsPause = false

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: store.company?.name ?? CitadelApp.displayName, crumb: crumb) {
                HStack(spacing: skin.size.s8) {
                    AinkradIconButton(systemName: "plus", size: skin.size.s30, tooltip: "New goal for the CEO") {}
                        .outlineBox().disabled(true)
                    AinkradIconButton(
                        systemName: allPaused ? "play.fill" : "pause.fill", size: skin.size.s30,
                        tooltip: allPaused ? "Resume all agents" : "Pause all runs"
                    ) {
                        if allPaused { store.setCompanyPaused(false) } else { confirmsPause = true }
                    }
                    .outlineBox().disabled(model.agents.isEmpty)
                    AinkradMenuButton(items: [
                        AinkradMenuItem(title: "Open Cost", systemName: "dollarsign") { store.screen = .cost }
                    ]) {
                        Image(systemName: "ellipsis")
                    }
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s14) {
                    if let alert = accountAlert { AccountWarning(text: alert) { store.screen = .accounts } }
                    tiles
                    if !openRequirements.isEmpty { requirements }
                    if !model.liveRuns.isEmpty { LiveRunStrip(store: store, model: model) }
                    HStack(alignment: .top, spacing: skin.size.s14) {
                        // The mockup's 1.35fr / 1fr columns.
                        NeedsYouTile(store: store, model: model)
                            .frame(width: max(0, (pageWidth - skin.size.s14) * 1.35 / 2.35))
                            .frame(maxHeight: .infinity)
                        SpendTile(store: store, model: model).frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: {
                    pageWidth = $0
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.top, skin.size.s2)
                .padding(.bottom, skin.size.s20)
            }
            .offlineDimmed()
        }
        .ainkradConfirmDialog(
            isPresented: $confirmsPause, title: "Pause all runs?",
            message:
                "Every agent finishes its current tool call, then parks; new wakes queue until you resume. Nothing is killed.",
            confirmTitle: "Pause all"
        ) { store.setCompanyPaused(true) }
    }

    /// Every agent paused (a hire still pending doesn't count): ⏸ turns into ▶ Resume.
    private var allPaused: Bool {
        let hired = model.agents.values.filter { !$0.isHirePending && $0.status != "terminated" }
        return !hired.isEmpty && hired.allSatisfy(\.isPaused)
    }

    /// `18 agents · 2 departments · Sprint CIT S4 day 6 of 10 · ● live`.
    private var crumb: Text {
        var parts = ["\(model.agents.count) agents", "\(model.departments.count) departments"]
        if let sprint = model.sprint {
            var text = "Sprint \(sprint.projectKey) \(sprint.name)"
            if let start = sprint.startsOn, let end = sprint.endsOn {
                let day = Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0
                let length = Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0
                text += " day \(day + 1) of \(length + 1)"
            }
            parts.append(text)
        }
        let live = store.streamStatus == .live
        return Text(parts.joined(separator: " · ")).foregroundStyle(skin.color(skin.text.muted))
            + Text(verbatim: " · ").foregroundStyle(skin.color(skin.text.muted))
            + Text(live ? "● live" : "● polling").foregroundStyle(live ? status.success : status.warning)
    }

    /// "claude-work is at its 5 h limit until 13:05 — runs move on. codex-pro at 86% of its 5 h window."
    private var accountAlert: String? {
        let lines = model.accounts.values.sorted { $0.id < $1.id }.compactMap { account -> String? in
            let window = account.windowSecs.map { " \($0 / 3600) h" } ?? ""
            if account.status == "limited" {
                let until = account.statusUntil.map { " until \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
                return "\(account.label) is at its\(window) limit\(until) — skipped, runs move to the next account."
            }
            if let use = account.windowUse, use * 100 >= Double(account.warnPercent ?? 80) {
                return "\(account.label) at \(Int(use * 100))% of its\(window) window."
            }
            return nil
        }
        return lines.isEmpty ? nil : lines.joined(separator: " ")
    }

    // MARK: - Tiles

    private var tiles: some View {
        let approvals = model.approvals.count
        let stuck = model.stuck.count
        let spend = model.spend
        return HStack(alignment: .top, spacing: skin.size.s14) {
            KPITile(
                label: "Needs you", value: "\(model.needsYouCount)", unit: nil,
                tone: model.needsYouCount > 0 ? status.warning : nil, rim: model.needsYouCount > 0 ? .warning : nil,
                detail: Text("\(approvals) approval\(approvals == 1 ? "" : "s") · \(stuck) stuck"))
            KPITile(
                label: "Working now", value: "\(model.liveRuns.count)", unit: "runs", tone: nil,
                detail: Text(
                    "\(model.busyAgents) agents busy · \(model.idleAgents) idle · \(model.pausedAgents) paused"))
            KPITile(
                label: "Spend today", value: model.spendToday.map { Fmt.dollars(micros: $0.costMicros) } ?? "—",
                unit: nil, tone: nil, detail: spendDetail(spend))
            KPITile(
                label: model.sprint.map { "Sprint \($0.projectKey) \($0.name)" } ?? "Sprint",
                value: model.sprint.map { "\($0.completed)" } ?? "—",
                unit: model.sprint.map { "/ \($0.committed) pts" }, tone: nil, detail: nil,
                progress: model.sprint.map { (Double($0.completed), Double(max($0.committed, 1))) })
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func spendDetail(_ spend: SpendInfo?) -> Text {
        let today = model.spendToday
        let unpricedRuns = today?.unpricedRuns ?? 0
        let unpriced =
            unpricedRuns > 0
            ? Text("\(unpricedRuns) unpriced run\(unpricedRuns == 1 ? "" : "s")").foregroundStyle(status.warning)
            : Text("\(Fmt.tokens(today?.tokens ?? 0)) tokens")
        guard let spend else { return unpriced }
        return unpriced + Text(" · \(Fmt.tokens(spend.subscriptionTokens)) subscription tokens")
    }

    // MARK: - Requirements

    private var openRequirements: [RequirementInfo] {
        model.requirements.filter { $0.state != "done" && $0.state != "cancelled" }
            .sorted { ($0.state == "plan_review" ? 0 : 1, -$0.id) < ($1.state == "plan_review" ? 0 : 1, -$1.id) }
    }

    private var requirements: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            TileHead(title: "Requirements", action: "All \(openRequirements.count) →") { store.screen = .requirements }
            HStack(alignment: .top, spacing: skin.size.s10) {
                ForEach(openRequirements.prefix(3), id: \.id) { requirement in
                    RequirementCard(requirement: requirement, model: model) { store.screen = .requirements }
                        .frame(maxWidth: .infinity)
                }
                ForEach(0..<max(0, 3 - openRequirements.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                }
            }
        }
    }
}

/// One of the four tiles: label, a big number with a small unit, a line under it (or a progress bar).
private struct KPITile: View {
    let label: String
    let value: String
    let unit: String?
    let tone: Color?
    var rim: AinkradChartTone?
    let detail: Text?
    var progress: (Double, Double)?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(skin.labelCased(label))
                    .citadelFont("t10", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.muted))
                    .lineLimit(1)
                HStack(alignment: .firstTextBaseline, spacing: skin.size.s4) {
                    Text(value)
                        .citadelFont("t26", weight: "semibold")
                        .foregroundStyle(tone ?? skin.color(skin.text.primary))
                        .contentTransition(.numericText())
                        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: value)
                    if let unit {
                        Text(unit).citadelFont("t13", weight: "medium").foregroundStyle(skin.color(skin.text.muted))
                    }
                }
                if let progress {
                    AinkradBudgetBar(
                        label: label, value: progress.0, limit: progress.1, warnFraction: nil, showsHardLimit: false
                    )
                    .padding(.top, skin.size.s8)
                }
                if let detail {
                    detail.citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
        .rim(rim)
    }
}

/// A requirement: key, title, the one thing blocking you, progress by points, ETA, owner.
private struct RequirementCard: View {
    let requirement: RequirementInfo
    let model: CompanyModel
    let open: () -> Void
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    private var needsPlan: Bool { requirement.state == "plan_review" }

    var body: some View {
        AinkradCard(onTap: open) {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                HStack(spacing: skin.size.s8) {
                    Text(requirement.key).citadelFont("t10_5", mono: true).foregroundStyle(theme.accentSecondary)
                    Text(requirement.title).citadelFont("t13", weight: "medium").lineLimit(1)
                        .foregroundStyle(skin.color(skin.text.primary))
                    Spacer(minLength: skin.size.s4)
                    if needsPlan { AinkradBadge(text: "plan", status: .warning) }
                }
                AinkradBudgetBar(
                    label: requirement.key, value: Double(requirement.donePoints),
                    limit: Double(max(requirement.points, 1)), warnFraction: nil, showsHardLimit: false)
                meta.citadelFont("t11").lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .rim(needsPlan ? .warning : nil)
    }

    private var meta: Text {
        let faint = skin.color(skin.text.faint)
        if needsPlan {
            return Text("\(requirement.points) pts planned · ").foregroundStyle(faint)
                + Text("approve plan to start").foregroundStyle(status.warning)
        }
        var parts = ["\(requirement.donePoints) / \(requirement.points) pts"]
        if let eta = requirement.eta { parts.append("ETA \(Fmt.eta(eta))") }
        if let owner = model.agent(requirement.ownerAgentID) { parts.append("PO \(owner.name)") }
        return Text(parts.joined(separator: " · ")).foregroundStyle(faint)
    }
}

/// The amber strip over the tiles when an account is at or near a window limit (E15.15, #11).
private struct AccountWarning: View {
    let text: String
    let open: () -> Void

    var body: some View {
        AinkradBanner(message: text, status: .warning, actionTitle: "Accounts →", action: open)
    }
}
