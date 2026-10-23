import AinkradAppKit
import SwiftUI

/// Screen 05: a run's live transcript over the event stream — assistant text, tool cards with diffs, redacted
/// secrets as chips, provider drops inline — with the pending approval docked above the composer and the rail's
/// meter, liveness, repos, stage timings, account and model.
struct RunView: View {
    let store: CitadelStore
    let model: CompanyModel
    let runID: Int64
    @State private var followsLive = true
    @State private var draft = ""
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        if let run = model.runs[runID] {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    header(run)
                    if run.hasNoTranscript(model.transcripts[runID]) {
                        NoTranscriptView(store: store, model: model, run: run)
                    } else {
                        transcript(run)
                    }
                    if let approval = model.waitingApproval(run: runID) {
                        decisionBar(approval, run: run)
                            .transition(.move(edge: .bottom).combined(with: .opacity))
                    }
                    composer(run)
                }
                .frame(maxWidth: .infinity)
                .animation(
                    reduceMotion ? nil : skin.animation(skin.motion.present),
                    value: model.waitingApproval(run: runID)?.id)
                RunRail(store: store, model: model, run: run)
            }
            .offlineDimmed()
        } else {
            AinkradEmptyState(
                icon: "play", title: "Loading the run", message: "Its transcript replays from the first event."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    // MARK: - Header

    private func header(_ run: RunInfo) -> some View {
        let agent = model.agent(run.agentID)
        let issue = model.issue(run.issueID)
        return HStack(alignment: .center, spacing: skin.size.s10) {
            if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s32) }
            VStack(alignment: .leading, spacing: skin.size.s2) {
                (Text(issue.map { "\($0.key) " } ?? "").foregroundStyle(theme.accentSecondary)
                    .font(skin.font(AinkradFontToken(sizeKey: "t15", mono: "family")))
                    + Text(issue?.title ?? "Run #\(run.id)").foregroundStyle(skin.color(skin.text.primary)))
                    .citadelFont("t15", weight: "semibold").lineLimit(1)
                HStack(spacing: skin.size.s6) {
                    Text(agent?.name ?? "Agent")
                    AinkradBadge(
                        text: AgentLook.harnessName(run.harness),
                        tint: AgentLook.harness(run.harness)?.color ?? theme.foreground)
                    Text(run.model ?? agent?.model ?? "").citadelFont("t11", mono: true)
                    if let account = run.accountID.flatMap({ model.accounts[$0] }) {
                        Text("· \(account.label)").citadelFont("t11", mono: true)
                    }
                    Text("· run #\(run.id)").citadelFont("t11", mono: true)
                    AinkradBadge(
                        text: stateWord(run),
                        status: run.isLive ? .neutral : run.state == "succeeded" ? .success : .danger)
                }
                .citadelFont("t11")
                .foregroundStyle(skin.color(skin.text.muted))
                .lineLimit(1)
            }
            Spacer(minLength: skin.size.s10)
            AinkradToggleButton(isOn: $followsLive, systemName: "arrow.down.to.line")
                .ainkradTooltip("Follow live")
            // Stop needs a server endpoint (not in the API yet).
            AinkradButton(title: "Stop", style: .danger, icon: "stop.fill") {}
                .outlined().tintedFill().compact().fixedSize().disabled(true)
            AinkradMenuButton(items: [
                AinkradMenuItem(title: "Copy run id", systemName: "doc.on.doc") {
                    NSPasteboard.general.clearContents()
                    NSPasteboard.general.setString(String(run.id), forType: .string)
                }
            ]) { Image(systemName: "ellipsis") }
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.top, skin.size.s14)
        .padding(.bottom, skin.size.s8)
    }

    private func stateWord(_ run: RunInfo) -> String {
        guard run.isLive else { return run.endWord }
        return "\(run.state) \(Fmt.duration(Date().timeIntervalSince(run.startedAt ?? run.queuedAt)))"
    }

    // MARK: - Transcript

    private func transcript(_ run: RunInfo) -> some View {
        let items = Transcript.items(
            model.transcripts[runID] ?? [], notes: model.notes[runID] ?? [], runState: run.state,
            waitingRequest: model.waitingApproval(run: runID)?.fields["request"])
        let repos = run.issueID.flatMap { model.issueRepos[$0] }?.count ?? 0
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: skin.size.s12) {
                    Text(statusLine(run, worktrees: repos))
                        .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                        .frame(maxWidth: .infinity)
                    ForEach(items) { item in
                        TranscriptRow(item: item, isLive: run.isLive)
                            .transition(.offset(y: skin.size.s6).combined(with: .opacity))
                    }
                    Color.clear.frame(height: skin.size.s1).id("end")
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.bottom, skin.size.s12)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: items.count)
            }
            .onChange(of: items.count) { _, _ in
                guard followsLive else { return }
                withAnimation(reduceMotion ? nil : skin.animation(skin.motion.present)) {
                    proxy.scrollTo("end", anchor: .bottom)
                }
            }
            .onAppear { if followsLive { proxy.scrollTo("end", anchor: .bottom) } }
        }
    }

    /// "Run started · context: 11.2k tokens · 2 worktrees".
    private func statusLine(_ run: RunInfo, worktrees: Int) -> String {
        var parts = ["Run started"]
        if let context = run.contextTokens { parts.append("context: \(Fmt.tokens(context)) tokens") }
        if worktrees > 1 { parts.append("\(worktrees) worktrees") }
        return parts.joined(separator: " · ")
    }

    // MARK: - Approval and composer

    private func decisionBar(_ approval: ApprovalInfo, run: RunInfo) -> some View {
        let who = model.agent(run.agentID)?.name ?? "the agent"
        let what = ToolLine.line(approval.fields)
        return AinkradDecisionBar(
            icon: "bolt.fill", iconTint: .secondary, caption: "Permission escalation",
            title: "Let \(who) run \(what)",
            actions: [
                .init(title: "Deny", style: .ghost) { store.decide(approval, approve: false) }.borderless(),
                .init(title: "Allow once", style: .primary) { store.decide(approval, approve: true) },
            ]
        )
        .labelCasedCaption()
        .padding(.horizontal, skin.size.s20)
        .padding(.bottom, skin.size.s8)
    }

    private func composer(_ run: RunInfo) -> some View {
        // Messaging a running agent needs a server endpoint (not in the API yet): the composer is shown, read-only.
        AinkradComposer(
            text: $draft,
            placeholder:
                "Message \(model.agent(run.agentID)?.name ?? "the agent") — delivered at its next turn (it keeps running)",
            isEditable: false, canSend: false, autoFocus: false, suggestions: { _ in [] }, onPick: { _, _ in },
            onDrop: nil, onSend: {}, chips: { EmptyView() }, leading: { EmptyView() }, trailing: { EmptyView() }
        )
        .padding(.horizontal, skin.size.s20)
        .padding(.bottom, skin.size.s14)
    }
}

/// One transcript item: assistant text (with its redactions as chips), a tool card, or an amber system line.
private struct TranscriptRow: View {
    let item: TranscriptItem
    let isLive: Bool
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        switch item {
        case .text(_, let text, let secrets):
            VStack(alignment: .leading, spacing: skin.size.s6) {
                AinkradMarkdownText(text: Redaction.masked(text))
                if !secrets.isEmpty { chips(secrets) }
            }
        case .note(_, let text):
            Text("↯ \(text)").citadelFont("t11").foregroundStyle(status.warning).frame(maxWidth: .infinity)
        case .tool(let call):
            AinkradToolCard(
                name: call.name, argument: call.argument, status: call.status, result: call.result,
                footnote: call.footnote,
                isInitiallyExpanded: call.edit != nil || !call.secrets.isEmpty || call.status == .failed
            ) {
                VStack(alignment: .leading, spacing: skin.size.s6) {
                    if let edit = call.edit {
                        AinkradDiffReview(
                            fileDiff: AinkradDiffEngine.compute(
                                old: edit.old, new: edit.new, path: edit.path, context: 1),
                            rejectedHunkIDs: .constant([])
                        )
                        .hidesHeader().editorLines().bareHunks().lineNumberGutter()
                    }
                    if let output = call.output { AinkradCodeBlock(Redaction.masked(output)) }
                    if !call.secrets.isEmpty { chips(call.secrets) }
                }
            }
        }
    }

    private func chips(_ names: [String]) -> some View {
        HStack(spacing: skin.size.s6) {
            ForEach(Array(Set(names)).sorted(), id: \.self) {
                AinkradRedactedChip($0, reason: "Redacted by the server before it was written to the log")
            }
        }
    }
}
