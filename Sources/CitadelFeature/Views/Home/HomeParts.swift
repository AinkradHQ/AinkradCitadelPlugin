import AinkradAppKit
import SwiftUI

/// "Live runs": one card per running run — the agent's figure, the issue, the tool call happening now (breathing
/// while it runs), and tokens against the run's cap with the warn mark. Click opens the live transcript.
struct LiveRunStrip: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            TileHead(title: "Live runs", action: "All runs →") { store.screen = .runs }
            HStack(alignment: .top, spacing: skin.size.s10) {
                ForEach(model.liveRuns.prefix(4)) { run in
                    RunCard(run: run, model: model) { store.open(.run(run.id)) }.frame(maxWidth: .infinity)
                }
                ForEach(0..<max(0, 4 - model.liveRuns.count), id: \.self) { _ in
                    Color.clear.frame(maxWidth: .infinity, maxHeight: 0)
                }
            }
        }
    }
}

struct RunCard: View {
    let run: RunInfo
    let model: CompanyModel
    let open: () -> Void
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let state = model.cardState(of: run)
        let tone = state.tone.map(color)
        AinkradCard(onTap: open) {
            VStack(alignment: .leading, spacing: skin.size.s4) {
                HStack(spacing: skin.size.s8) {
                    if let agent = model.agent(run.agentID) {
                        AgentFigure(agent: agent, model: model, size: skin.size.s24)
                    }
                    Text(model.agent(run.agentID)?.name ?? "Agent").citadelFont("t13", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                    Spacer(minLength: skin.size.s4)
                    if let word = state.word {
                        AinkradBadge(text: word, status: state.tone == .danger ? .danger : .warning)
                    } else {
                        Text(Fmt.age(Date().timeIntervalSince(run.startedAt ?? run.queuedAt)))
                            .citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    }
                }
                issueLine.lineLimit(1).padding(.top, skin.size.s2)
                toolLine(state.word)
                AinkradBudgetBar(
                    label: "Run tokens", value: Double(run.tokens), limit: Double(model.runCap ?? 0),
                    warnFraction: model.warnFraction, showsHardLimit: false,
                    tone: state.tone == .warning ? .warning : nil
                )
                .padding(.top, skin.size.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardRim(tone)
    }

    private var issueLine: Text {
        let issue = model.issue(run.issueID)
        return Text(issue.map { "\($0.key) " } ?? "").foregroundStyle(theme.accentSecondary)
            .font(skin.font(AinkradFontToken(sizeKey: "t11", mono: "family")))
            + Text(issue?.title ?? "Run #\(run.id)").foregroundStyle(skin.color(skin.text.primary))
    }

    @ViewBuilder private func toolLine(_ word: String?) -> some View {
        let waiting = model.waitingApproval(run: run.id)
        let silent = Date().timeIntervalSince(run.lastProgressAt ?? run.startedAt ?? run.queuedAt)
        Group {
            if let waiting {
                Text(
                    "⌁ asks to \(ToolLine.line(waiting.fields).isEmpty ? "run a tool" : ToolLine.line(waiting.fields))"
                )
                .foregroundStyle(skin.color(skin.text.muted))
            } else if word == "stalled" {
                Text("⏸ silent \(Int(silent / 60))m · watchdog at \(Int((model.stallAfter ?? 0) / 60))m")
                    .foregroundStyle(status.danger)
            } else {
                Text("▸ \(model.toolNow[run.id] ?? run.state)").foregroundStyle(skin.color(skin.text.muted))
                    .breathing(run.state == "running")
            }
        }
        .citadelFont("t10_5", mono: true)
        .lineLimit(1)
        .truncationMode(.tail)
    }

    private func color(_ tone: NeedsItem.Tone) -> Color {
        switch tone {
        case .accent: theme.accentPrimary
        case .warning: status.warning
        case .danger: status.danger
        }
    }
}

/// "What needs you now": each row with its one obvious action inline; the chevron opens the detail.
struct NeedsYouTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let items = model.needsItems()
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                TileHead(title: "What needs you now", action: "Open inbox →") { store.screen = .approvals }
                if items.isEmpty {
                    Text("Nothing needs you. Agents ask here when they do.")
                        .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                }
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    ForEach(items) { item in
                        row(item).transition(.move(edge: .top).combined(with: .opacity))
                    }
                }
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: items.map(\.id))
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }

    private func row(_ item: NeedsItem) -> some View {
        AinkradListRow(
            onTap: { perform(item.action, chevron: true) },
            leading: {
                AinkradBadge(text: item.glyph, tint: tint(item.tone))
            }, title: item.title, subtitle: item.subtitle.isEmpty ? nil : item.subtitle,
            trailing: {
                switch item.action {
                case .approve(_, let title):
                    AinkradButton(title: title, style: .primary) { perform(item.action, chevron: false) }
                        .compact().fixedSize()
                case .openScreen(_, let title):
                    AinkradButton(title: title, style: .secondary) { perform(item.action, chevron: false) }
                        .secondaryAccent().compact().fixedSize()
                case .openRun:
                    AinkradButton(title: "Open run", style: .secondary) { perform(item.action, chevron: false) }
                        .secondaryAccent().compact().fixedSize()
                }
            })
    }

    private func perform(_ action: NeedsItem.Action, chevron: Bool) {
        switch action {
        case .approve(let approval, _):
            if chevron { store.screen = .approvals } else { store.decide(approval, approve: true) }
        case .openRun(let run): store.open(.run(run))
        case .openScreen(let screen, _): store.screen = screen
        }
    }

    private func tint(_ tone: NeedsItem.Tone) -> Color {
        switch tone {
        case .accent: theme.accentPrimary
        case .warning: status.warning
        case .danger: status.danger
        }
    }
}

/// Spend: priced / unpriced / subscription (an unpriced run is never $0), then the budgets closest to their line.
struct SpendTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                TileHead(title: "Spend", action: "Cost →") { store.screen = .cost }
                // The server reports spend to date; an hourly series for the day is not served yet.
                AinkradLineChart(title: "Spend today", series: [], emptyMessage: "No hourly spend from the server yet")
                    .frame(height: skin.size.s70)
                if let spend = model.spend {
                    AinkradStackedStatusBar(runs: [
                        AinkradStatusRun(count: Int(spend.pricedTokens), status: .neutral),
                        AinkradStatusRun(count: Int(spend.unpricedTokens), status: .warning),
                        AinkradStatusRun(count: Int(spend.subscriptionTokens), status: .success),
                    ])
                    Text(
                        "Priced \(Fmt.dollars(micros: spend.costMicros)) · Unpriced \(spend.unpricedRuns) runs · Subscription \(Fmt.tokens(spend.subscriptionTokens)) tok"
                    )
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                }
                Text(skin.labelCased("Budgets near the line")).citadelFont("t10", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.muted)).padding(.top, skin.size.s6)
                ForEach(model.budgets.sorted { $0.fraction > $1.fraction }.prefix(3)) { budget in
                    HStack(spacing: skin.size.s12) {
                        Text("\(budget.label) · \(budget.period)").citadelFont("t12")
                            .foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
                        Spacer(minLength: skin.size.s8)
                        AinkradBudgetBar(
                            label: budget.label, value: Double(budget.spent), limit: Double(budget.cap),
                            warnFraction: budget.warnFraction, showsHardLimit: false
                        )
                        .frame(width: skin.size.s150)
                    }
                }
                if model.budgets.isEmpty {
                    Text("No budgets set").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension View {
    /// The live tool line's breath (opacity 0.55 ↔ 1 over the skin's breathe period) while a tool runs; still
    /// when it ends, under Reduce Motion, or when the motion budget is frozen.
    func breathing(_ isActive: Bool) -> some View { modifier(Breathing(isActive: isActive)) }
}

private struct Breathing: ViewModifier {
    let isActive: Bool
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        if isActive, !reduceMotion {
            BudgetedTimelineView { date in
                content.opacity(Self.level(date, period: skin.motion.durations.breathe, floor: skin.opacity.o55))
            }
        } else {
            content
        }
    }

    static func level(_ date: Date, period: Double, floor: Double) -> Double {
        guard period > 0 else { return 1 }
        let phase = date.timeIntervalSinceReferenceDate.truncatingRemainder(dividingBy: period) / period
        return floor + (1 - floor) * (0.5 + 0.5 * cos(2 * Double.pi * phase))
    }
}
