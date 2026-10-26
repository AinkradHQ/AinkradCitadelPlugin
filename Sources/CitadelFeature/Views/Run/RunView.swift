import AinkradAppKit
import SwiftUI

/// The Run screen (prototype `run.js`): the hero and dock, the transcript (agent turns, your messages, flat tool
/// cards, system lines), follow-live with a "Jump to latest · N new" pill, the docked decision and the composer while
/// it runs — an end summary instead once it ended — and the rail of cards.
struct RunView: View {
    let store: CitadelStore
    let model: CompanyModel
    let runID: Int64
    @State private var followsLive = true
    @State private var fresh = 0
    @State private var confirmsStop = false
    /// Scroll-position changes are ignored while the view scrolls itself to the end.
    @State private var autoScrollUntil = Date.distantPast
    @State private var jumpRequest = 0
    /// Where the transcript's first and last lines sit in its viewport.
    @State private var lastTop: CGFloat?
    @State private var endY: CGFloat = 0
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.ainkradMotionBudget) private var motionBudget

    var body: some View {
        if let run = model.runs[runID] {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    RunHero(
                        store: store, model: model, run: run, followsLive: followsLive,
                        toggleFollow: {
                            if followsLive { followsLive = false } else { jump() }
                        }, stop: { confirmsStop = true })
                    if run.hasNoTranscript(model.transcripts[runID]) {
                        NoTranscriptView(store: store, model: model, run: run)
                    } else {
                        transcript(run)
                            .overlay(alignment: .bottom) { jumpPill }
                    }
                    if run.isLive {
                        RunDecision(store: store, model: model, run: run)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                        RunComposer(store: store, model: model, run: run) { jump() }
                    } else {
                        RunEndSummary(store: store, model: model, run: run)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                }
                .frame(maxWidth: .infinity)
                .animation(
                    reduceMotion ? nil : skin.animation(skin.motion.present),
                    value: model.waitingApproval(run: runID)?.id
                )
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: run.isLive)
                RunRail(store: store, model: model, run: run)
            }
            .offlineDimmed()
            .ainkradConfirmDialog(
                isPresented: $confirmsStop, title: "Stop run #\(run.id) now?",
                message:
                    "\(model.agent(run.agentID)?.name ?? "The agent") is killed mid-step. The worktree and branch are kept; nothing is merged.",
                confirmTitle: "Stop run", isDestructive: true
            ) { store.stopWithToast(run) }
        } else if model.companyRuns == nil {
            AinkradEmptyState(
                icon: "play", title: "Loading the run", message: "Its transcript replays from the first event."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            VStack(spacing: skin.size.s10) {
                AinkradEmptyState(
                    icon: "play", title: "This run's transcript was pruned",
                    message: "Transcripts are kept for a limited time; this one is gone.")
                AinkradDockButton("All runs", height: skin.size.s26) { store.screen = .runs }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func jump() {
        followsLive = true
        fresh = 0
        jumpRequest += 1
    }

    // MARK: - Transcript

    private func transcript(_ run: RunInfo) -> some View {
        let waiting = model.waitingApproval(run: runID)
        let items = Transcript.items(
            model.transcripts[runID] ?? [], notes: model.notes[runID] ?? [], runState: run.state,
            waitingRequest: waiting?.fields["request"])
        let lastText = items.last.flatMap { if case .text = $0 { $0.id } else { nil } }
        let agent = model.agent(run.agentID)
        let look = model.look(run)
        return GeometryReader { viewport in
            ScrollViewReader { proxy in
                ScrollView {
                    VStack(alignment: .leading, spacing: skin.size.s16) {
                        TranscriptSysLine(text: statusLine(run))
                            .background(
                                GeometryReader { top in
                                    Color.clear.preference(
                                        key: TranscriptTopKey.self, value: top.frame(in: .named("transcript")).minY)
                                })
                        ForEach(items) { item in
                            row(
                                item, run: run, agent: agent, waiting: waiting,
                                streaming: item.id == lastText && look.key == "running"
                            )
                            .transition(.offset(y: skin.size.s8).combined(with: .opacity))
                        }
                        if let line = closingLine(run, look: look) {
                            TranscriptSysLine(text: line, tint: Hue(look.tone).color(skin))
                        }
                        Color.clear.frame(height: skin.size.s1).id("end")
                            .background(
                                GeometryReader { end in
                                    Color.clear.preference(
                                        key: TranscriptEndKey.self, value: end.frame(in: .named("transcript")).maxY)
                                })
                    }
                    .padding(.horizontal, skin.size.s24)
                    .padding(.top, skin.size.s4)
                    .padding(.bottom, skin.size.s20)
                    .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: items.count)
                }
                .coordinateSpace(name: "transcript")
                .onPreferenceChange(TranscriptTopKey.self) { topY in
                    // The top moving is the reader scrolling; content growing below leaves it in place.
                    defer { lastTop = topY }
                    guard Date() > autoScrollUntil, let lastTop, abs(topY - lastTop) > skin.size.s1 else { return }
                    let atEnd = endY - viewport.size.height < skin.size.s40
                    if atEnd, !followsLive {
                        followsLive = true
                        fresh = 0
                    } else if !atEnd, followsLive {
                        followsLive = false
                    }
                }
                .onPreferenceChange(TranscriptEndKey.self) { endY = $0 }
                .onChange(of: items.count) { old, new in
                    guard new > old else { return }
                    if followsLive, motionBudget != .frozen {
                        scrollToEnd(proxy)
                    } else if !followsLive {
                        fresh += new - old
                    }
                }
                .onChange(of: jumpRequest) { _, _ in scrollToEnd(proxy) }
                .onAppear {
                    guard motionBudget != .frozen else { return }
                    autoScrollUntil = Date().addingTimeInterval(0.6)
                    proxy.scrollTo("end", anchor: .bottom)
                    DispatchQueue.main.async { proxy.scrollTo("end", anchor: .bottom) }
                }
            }
        }
    }

    private func scrollToEnd(_ proxy: ScrollViewProxy) {
        autoScrollUntil = Date().addingTimeInterval(0.6)
        withAnimation(reduceMotion ? nil : skin.animation(skin.motion.present)) {
            proxy.scrollTo("end", anchor: .bottom)
        }
    }

    @ViewBuilder
    private func row(
        _ item: TranscriptItem, run: RunInfo, agent: AgentInfo?, waiting: ApprovalInfo?, streaming: Bool
    ) -> some View {
        switch item {
        case .text(_, let text, let secrets):
            TranscriptTurn(agent: agent, model: model, text: text, secrets: secrets, streaming: streaming)
        case .note(_, let text):
            TranscriptSysLine(text: "↷ \(text)", tint: skin.color(skin.palette.warning))
        case .you(_, let text):
            TranscriptYou(text: text)
        case .tool(let call):
            RunToolCard(
                call: call, isLive: run.isLive,
                note: call.status == .waiting
                    ? waiting?.fields["reason"]
                        ?? "Outside this project's permission policy — it waits for your decision."
                    : nil,
                copy: store.copy)
        }
    }

    /// "Run started · context: 3 skills, 2 landmines, issue + 4 comments · 11.2k tokens · 2 worktrees".
    private func statusLine(_ run: RunInfo) -> String {
        var parts = ["Run started"]
        if let context = run.contextTokens {
            parts.append("\(Fmt.tokens(context)) tokens")
            let worktrees = run.issueID.flatMap { model.issueRepos[$0] }?.count ?? 0
            if worktrees > 1 { parts.append("\(worktrees) worktrees") }
        } else {
            if let runner = run.runnerID.flatMap({ model.runners[$0] }) { parts.append(runner) }
        }
        return parts.joined(separator: " · ")
    }

    /// The stall warning on a stalling run, or how an abnormal run ended.
    private func closingLine(_ run: RunInfo, look: RunLook) -> String? {
        switch look.key {
        case "stalled":
            let silent = Date().timeIntervalSince(run.lastProgressAt ?? run.startedAt ?? run.queuedAt)
            let limit = model.limit("run.stall_after_secs", project: model.issue(run.issueID)?.projectID)?.value
            return "⏸ No tool call, file change or message for \(Fmt.duration(silent))"
                + (limit.map { " · the watchdog stops it at \($0 / 60)m and escalates" } ?? "")
        case "runner_lost":
            return "⚑ Runner stopped heartbeating · lease expired after 30 s · run ended runner_lost"
        case "succeeded", "running", "queued", "paused", "waiting": return nil
        default:
            let reason = run.terminalReason.flatMap { $0.isEmpty ? nil : " · \($0)" } ?? ""
            return "\(look.glyph) Run ended \(look.word)\(reason)"
        }
    }

    // MARK: - Jump pill

    @ViewBuilder private var jumpPill: some View {
        AinkradTapArea(action: jump) {
            Text("↓ Jump to latest\(fresh > 0 ? " · \(fresh) new" : "")").citadelFont("t11")
                .foregroundStyle(skin.color(.palette("foreground", 1)))
                .padding(.horizontal, skin.size.s14)
                .padding(.vertical, skin.size.s5)
                .background(
                    skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o85),
                    in: RoundedRectangle(cornerRadius: skin.size.s8))
        }
        .keyboardShortcut(.downArrow, modifiers: .command)
        .opacity(followsLive ? 0 : 1)
        .offset(y: followsLive ? skin.size.s12 : 0)
        .allowsHitTesting(!followsLive)
        .padding(.bottom, skin.size.s16)
        .animation(
            skin.animation(AinkradAnimationToken(curve: "spring", response: 0.25, damping: 0.7)), value: followsLive)
    }
}

private struct TranscriptTopKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

private struct TranscriptEndKey: PreferenceKey {
    static let defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
