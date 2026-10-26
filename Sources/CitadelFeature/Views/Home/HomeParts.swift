import AinkradAppKit
import SwiftUI

/// "Live runs": a card per run in flight (prototype `runsLiveCard`), or the idle strip when nothing runs.
struct LiveRunsSection: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            AinkradSectionHead(title: "Live runs", count: "\(model.liveRuns.count)", link: "All runs →") {
                store.screen = .runs
            }
            .padding(.horizontal, skin.size.s2)
            if model.liveRuns.isEmpty {
                idle
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: skin.size.s260), spacing: skin.size.s12)],
                    spacing: skin.size.s12
                ) {
                    ForEach(model.liveRuns) { run in LiveRunCard(store: store, model: model, run: run) }
                }
            }
        }
    }

    /// `● Idle · last run #426 Rook on CIT-61 ended 11:32   [Runs →]`.
    private var idle: some View {
        let last = (model.companyRuns ?? []).first { !$0.isLive }
        return AinkradBentoTile(padding: skin.size.s12) {
            HStack(spacing: skin.size.s8) {
                Circle().fill(skin.color(skin.text.faint)).frame(width: skin.size.s7, height: skin.size.s7)
                Text("Idle").citadelFont("t12_5", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                if let last {
                    let who = model.agent(last.agentID)?.name ?? "an agent"
                    let on = model.issue(last.issueID).map { " on \($0.key)" } ?? ""
                    let at = (last.endedAt ?? last.queuedAt).formatted(date: .omitted, time: .shortened)
                    Text("· last run #\(last.id) \(who)\(on) ended \(at)").citadelFont("t12")
                        .foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
                }
                Spacer(minLength: skin.size.s8)
                AinkradDockButton("Runs") { store.screen = .runs }
            }
        }
    }
}

/// One live run: agent figure, name, role and runner, its state; the issue; the live console line; tokens
/// against the cap; elapsed and cost; the two actions that fit its state.
struct LiveRunCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    /// What a tap on the card does: Home opens the run, the Runs screen peeks it.
    var onOpen: (() -> Void)?
    @State private var hovering = false
    @State private var nudging = false
    @State private var nudge = ""
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var agent: AgentInfo? { model.agent(run.agentID) }
    private var waiting: ApprovalInfo? { model.waitingApproval(run: run.id) }
    private var state: (word: String?, tone: NeedsItem.Tone?) { model.cardState(of: run) }

    private var colors: (Color, Color) {
        switch state.tone {
        case .warning?: (status.warning, status.warning)
        case .danger?: (status.danger, status.danger)
        default:
            (
                agent?.palette.lightColor ?? skin.color(skin.palette.accentSecondary),
                agent?.palette.deepColor ?? skin.color(skin.palette.accentPrimary)
            )
        }
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        let cap = model.cap(of: run)
        VStack(alignment: .leading, spacing: skin.size.s10) {
            header
            issueLine
            console
            AinkradBudgetBar(
                label: "Run tokens", value: Double(run.tokens), limit: Double(cap ?? max(run.tokens, 1)),
                warnFraction: model.warnFraction, showsHardLimit: false, tone: state.tone == .warning ? .warning : nil)
            numbers
            actions
        }
        .padding(skin.size.s14)
        .background {
            ZStack(alignment: .topTrailing) {
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: colors.0.opacity(skin.opacity.o14), location: 0),
                            .init(color: skin.color(.palette("background", skin.opacity.o90)), location: 0.55),
                            .init(color: colors.1.opacity(skin.opacity.o10), location: 1),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                RadialGradient(
                    colors: [colors.0.opacity(skin.opacity.o20), .clear], center: .topTrailing, startRadius: 0,
                    endRadius: skin.size.s160
                )
                .clipShape(shape)
            }
        }
        .overlay(shape.strokeBorder(colors.0.opacity(hovering ? skin.opacity.o40 : skin.opacity.o25), lineWidth: 1))
        .shadow(
            color: skin.color(.palette("black", hovering ? skin.opacity.o35 : skin.opacity.o25)), radius: skin.size.s16,
            y: skin.size.s12
        )
        .offset(y: hovering && !reduceMotion ? -skin.size.s3 : 0)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .animation(
            skin.animation(AinkradAnimationToken(curve: "spring", response: 0.3, damping: 0.75)), value: hovering
        )
        .onTapGesture { if let onOpen { onOpen() } else { store.open(.run(run.id)) } }
        .ainkradPanelModal(isPresented: $nudging, contentWidth: skin.size.s420) { nudgeSheet }
    }

    private var header: some View {
        HStack(spacing: skin.size.s10) {
            if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s40, isActive: true) }
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(agent?.name ?? "Agent").citadelFont("t13", weight: "bold").foregroundStyle(
                    skin.color(skin.text.primary))
                (Text(agent?.role ?? "")
                    + Text(run.runnerID.flatMap { model.runners[$0] }.map { " · \($0)" } ?? "")
                    .font(skin.font(AinkradFontToken(sizeKey: "t11", mono: "family"))))
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            }
            Spacer(minLength: skin.size.s4)
            switch state.tone {
            case .warning?: AinkradStatePill(text: "waiting on you", tint: status.warning)
            case .danger?: AinkradStatePill(text: "stalling", tint: status.danger)
            default: AinkradStatePill(text: "running", tint: skin.color(skin.palette.accentSecondary), dot: true)
            }
        }
    }

    private var issueLine: some View {
        let issue = model.issue(run.issueID)
        return
            (Text(issue.map { "\($0.key) " } ?? "").font(
                skin.font(AinkradFontToken(sizeKey: "t12", weight: "bold", mono: "family"))
            )
            .foregroundStyle(skin.color(skin.palette.accentSecondary))
            + Text(issue?.title ?? model.runTitle(run)).foregroundStyle(skin.color(skin.text.primary)))
            .citadelFont("t13", weight: "medium")
            .lineLimit(2)
            .frame(minHeight: skin.size.s34, alignment: .topLeading)
    }

    private var console: some View {
        let silent = Date().timeIntervalSince(run.lastProgressAt ?? run.startedAt ?? run.queuedAt)
        return Group {
            if let waiting {
                let fallback = ToolLine.line(waiting.fields).isEmpty ? "run a tool" : ToolLine.line(waiting.fields)
                Text(waiting.fields["prompt"] ?? "asks to \(fallback)")
                    .foregroundStyle(status.warning)
            } else if state.tone == .danger {
                Text("⏸ silent \(Fmt.age(silent)) · watchdog at \(Int((model.stallAfter ?? 0) / 60))m")
                    .foregroundStyle(status.danger)
            } else {
                Text("▸ \(model.toolNow[run.id] ?? run.state)").foregroundStyle(skin.color(skin.text.muted))
                    .breathing(run.state == "running")
            }
        }
        .citadelFont("t11", mono: true)
        .lineLimit(1)
        .truncationMode(.tail)
        .padding(.horizontal, skin.size.s10)
        .frame(maxWidth: .infinity, minHeight: skin.size.s30, alignment: .leading)
        .background(
            skin.color(.palette("black", skin.opacity.o28)),
            in: RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous))
    }

    private var numbers: some View {
        let cap = model.cap(of: run)
        return HStack(spacing: skin.size.s8) {
            Text("\(Fmt.tokens(run.tokens)) / \(cap.map(Fmt.tokens) ?? "—")")
            Spacer(minLength: skin.size.s4)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                Text("⏱ \(Fmt.age(context.date.timeIntervalSince(run.startedAt ?? run.queuedAt)))")
            }
            Text(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "unpriced")
                .foregroundStyle(run.costMicros == nil ? status.warning : skin.color(skin.text.primary))
        }
        .citadelFont("t11", mono: true)
        .foregroundStyle(skin.color(skin.text.muted))
    }

    @ViewBuilder private var actions: some View {
        let height = skin.size.s30
        HStack(spacing: skin.size.s8) {
            if let waiting {
                let isBudget = waiting.kind == "budget_overrun" || waiting.fields["ask"] != nil
                AinkradDockButton(isBudget ? "Stop at cap" : "Deny", height: height, fillsWidth: true) {
                    store.decide(waiting, approve: false)
                }
                AinkradDockButton(
                    isBudget ? "Raise to \(waiting.fields["ask"] ?? "$6")" : "Allow once", tone: .primary,
                    height: height, fillsWidth: true
                ) {
                    store.decide(waiting, approve: true)
                    store.toast(
                        AinkradRichToast(
                            title: isBudget ? "Cap raised" : "Allowed once",
                            body: agent.map { "\($0.name) continues" }, status: .success))
                }
            } else if state.tone == .danger {
                AinkradDockButton("Stop", tone: .danger, height: height, fillsWidth: true) { store.stop(run: run.id) }
                AinkradDockButton("Nudge \(agent?.name ?? "")", tone: .primary, height: height, fillsWidth: true) {
                    nudge = "You've been quiet for a while — post where you are and what's blocking you."
                    nudging = true
                }
            } else {
                AinkradDockButton("Stop", height: height, fillsWidth: true) { store.stop(run: run.id) }
                AinkradDockButton("Transcript", height: height, fillsWidth: true) { store.open(.run(run.id)) }
            }
        }
    }

    private var nudgeSheet: some View {
        VStack(alignment: .leading, spacing: skin.size.s14) {
            HStack(spacing: skin.size.s12) {
                if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s44, isActive: true) }
                Text("Nudge \(agent?.name ?? "the agent")").citadelFont("t15", weight: "semibold")
            }
            AinkradTextArea(text: $nudge, placeholder: "Message")
                .frame(minHeight: skin.size.s80)
            Text("Delivered at its next turn · resets the watchdog").citadelFont("t11").foregroundStyle(
                skin.color(skin.text.faint))
            HStack {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { nudging = false }.fixedSize()
                AinkradButton(title: "Send ↵", style: .primary) {
                    let name = agent?.name ?? "The agent"
                    store.message(run: run.id, nudge) {
                        store.toast(
                            AinkradRichToast(
                                title: "Nudged \(name)", body: "Delivered at its next turn", status: .success))
                    }
                    nudging = false
                }
                .fixedSize()
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(skin.size.s4)
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

extension View {
    /// A Home row that opens something: a faint wash and a 2 pt nudge on hover, still under reduce-motion.
    func homeHoverRow(_ action: @escaping () -> Void) -> some View { modifier(HomeHoverRow(action: action)) }
}

private struct HomeHoverRow: ViewModifier {
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .background(
                RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
                    .fill(skin.color(.palette("foreground", hovering ? skin.opacity.o05 : 0)))
            )
            .offset(x: hovering && !reduceMotion ? skin.size.s2 : 0)
            .contentShape(Rectangle())
            .onHover { hovering = $0 }
            .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: hovering)
            .onTapGesture(perform: action)
            .focusable()
            .onKeyPress(keys: [.return, .space]) { _ in
                action()
                return .handled
            }
            .accessibilityElement(children: .combine)
            .accessibilityAddTraits(.isButton)
            .accessibilityAction(.default, action)
    }
}
