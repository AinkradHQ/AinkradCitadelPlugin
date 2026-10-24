import AinkradAppKit
import SwiftUI

/// Screen 07: agent threads — one agent on one issue, the depth view (decision #9: the requirement thread is where
/// you talk; this is not an inbox). The list shows the agent, the issue, its requirement, the last line, and
/// whether it waits on you (red when the last run died with no reply); the thread is the issue's comments with the
/// agent's runs between them.
struct ThreadsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let threads = model.threads()
        let current = store.selectedThread.flatMap { key in threads.first { $0.key == key } } ?? threads.first
        HStack(spacing: 0) {
            list(threads, current: current?.key)
                .frame(width: skin.size.s380)
                .background(theme.surface.opacity(skin.opacity.o20))
            Group {
                if let current {
                    ThreadDetail(store: store, model: model, key: current.key).id(current.key)
                } else {
                    AinkradEmptyState(
                        icon: "envelope", title: "No agent threads yet",
                        message: "A thread opens when an agent works an issue or asks you something on it.")
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: current?.key)
        }
        .offlineDimmed()
        .onChange(of: current?.key, initial: true) { _, key in if let key { store.openThread(key) } }
    }

    private func list(_ threads: [ThreadSummary], current: ThreadKey?) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Agent threads", crumb: Text("one agent · one issue · depth view"))
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    ForEach(threads) { thread in row(thread, isSelected: thread.key == current) }
                }
                .padding(.horizontal, skin.size.s10)
                .padding(.bottom, skin.size.s14)
            }
        }
    }

    private func row(_ thread: ThreadSummary, isSelected: Bool) -> some View {
        let agent = model.agent(thread.key.agentID)
        let issue = model.issue(thread.key.issueID)
        return AinkradListRow(
            isSelected: isSelected, onTap: { store.selectedThread = thread.key },
            leading: {
                if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s28) }
            },
            title: "\(issue?.key ?? "#\(thread.key.issueID)") · \(issue?.title ?? "")",
            subtitle: [thread.requirementKey ?? "no requirement", thread.lastLine].joined(separator: " · "),
            trailing: {
                if thread.waitingOnYou {
                    AinkradBadge(text: "you", status: .warning)
                } else if thread.died {
                    AinkradBadge(text: "died", status: .danger)
                } else if thread.at > .distantPast {
                    Text(Fmt.age(Date().timeIntervalSince(thread.at))).citadelFont("t10", mono: true)
                        .foregroundStyle(skin.color(skin.text.faint))
                }
            })
    }
}

/// One thread: the issue's state and next actor in the head, the hub banner when the open question is also in a
/// requirement thread, the conversation, and the composer — which posts a comment that answers the open
/// question (decision #44's auto-target) and wakes the agent.
private struct ThreadDetail: View {
    let store: CitadelStore
    let model: CompanyModel
    let key: ThreadKey
    @State private var draft = ""
    /// The agent the message wakes; `nil` is the thread's own agent.
    @State private var wakeTarget: Int64?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    private var agent: AgentInfo? { model.agent(key.agentID) }
    private var issue: IssueInfo? { model.issue(key.issueID) }
    private var question: QuestionInfo? { model.openQuestion(key) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "\(issue?.key ?? "") \(issue?.title ?? "")", crumb: crumb) {
                HStack(spacing: skin.size.s8) {
                    if let requirement = requirement {
                        AinkradIconButton(
                            systemName: "rhombus.fill", size: skin.size.s30,
                            tooltip: "Open the requirement thread (\(requirement.key))"
                        ) { store.screen = .requirements }
                        .outlineBox()
                    }
                    AinkradIconButton(systemName: "play.fill", size: skin.size.s30, tooltip: "Watch the run") {
                        if let run = latestRun { store.open(.run(run.id)) }
                    }
                    .outlineBox().disabled(latestRun == nil)
                }
            }
            if let issue { IssueControls(store: store, model: model, issue: issue) }
            IssuePRList(store: store, model: model, issue: key.issueID)
            if let question, let requirement = requirement, question.requirementID == requirement.id {
                AinkradBanner(
                    message:
                        "\(agent?.name ?? "The agent")'s question also appears in \(requirement.key) \(requirement.title). Answer here or there; both clear.",
                    status: .neutral, actionTitle: "Open \(requirement.key) →", action: { store.screen = .requirements }
                )
                .padding(.horizontal, skin.size.s20)
                .padding(.bottom, skin.size.s8)
            }
            conversation
            if let wake = model.wakes[key.issueID]?.last {
                SystemLine(text: wakeLine(wake)).padding(.bottom, skin.size.s6)
            }
            composer
        }
    }

    private var requirement: RequirementInfo? {
        issue?.requirementID.flatMap { id in model.requirements.first { $0.id == id } }
    }

    private var latestRun: RunInfo? {
        (model.agentRuns[key.agentID] ?? []).filter { $0.issueID == key.issueID }.max { $0.queuedAt < $1.queuedAt }
    }

    /// "with Quill (Writer) · waiting on you · next actor: you · $4.20 spent".
    private var crumb: Text {
        let muted = skin.color(skin.text.muted)
        var text = Text("with \(agent?.nameAndRole ?? "agent")").foregroundStyle(muted)
        if question != nil {
            text =
                text + Text(verbatim: " · ").foregroundStyle(muted)
                + Text(skin.labelCased("waiting on you")).foregroundStyle(status.warning)
        } else if let state = issue?.state, !state.isEmpty {
            text = text + Text(" · \(state.replacingOccurrences(of: "_", with: " "))").foregroundStyle(muted)
        }
        if let issue, let next = model.nextActorWord(issue) {
            text =
                text + Text(" · next actor: ").foregroundStyle(muted)
                + Text(next).foregroundStyle(skin.color(skin.text.primary)).bold()
        }
        if let cost = model.issueCosts[key.issueID] {
            text = text + Text(" · \(Fmt.dollars(micros: cost.costMicros))").foregroundStyle(muted)
        }
        return text
    }

    private var conversation: some View {
        let lines = model.conversation(key)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: skin.size.s14) {
                    if lines.isEmpty {
                        Text("No messages on \(issue?.key ?? "this issue") yet.").citadelFont("t12")
                            .foregroundStyle(skin.color(skin.text.faint)).frame(maxWidth: .infinity)
                    }
                    ForEach(lines) { line in lineView(line) }
                    Color.clear.frame(height: skin.size.s1).id("end")
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.vertical, skin.size.s10)
            }
            .onChange(of: lines.count, initial: true) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    @ViewBuilder private func lineView(_ line: ThreadLine) -> some View {
        switch line {
        case .comment(let comment):
            if let author = comment.agentID.flatMap({ model.agent($0) }) {
                AinkradChatBubble(text: comment.body, role: .agent, author: author.name, meta: author.role) {
                    AgentFigure(agent: author, model: model, size: skin.size.s28)
                }
            } else {
                AinkradChatBubble(text: comment.body, role: .user, author: "You")
            }
        case .run(let run):
            SystemLine(text: runLine(run))
        case .question(let question):
            VStack(alignment: .leading, spacing: skin.size.s8) {
                if let asker = model.agent(question.agentID) {
                    AinkradChatBubble(
                        text: question.text, role: .agent, author: asker.name,
                        meta: question.isOpen ? "asks you" : "asked · \(question.state)"
                    ) { AgentFigure(agent: asker, model: model, size: skin.size.s28) }
                }
                if question.isOpen, !question.options.isEmpty {
                    HStack(spacing: skin.size.s6) {
                        ForEach(question.options, id: \.self) { option in
                            AinkradButton(title: option, style: .secondary) {
                                store.send(option, on: key.issueID, waking: key.agentID)
                            }
                            .secondaryAccent().compact().fixedSize()
                        }
                    }
                    .padding(.leading, skin.size.s40)
                }
            }
        }
    }

    /// "▶ Run #422 · 11:14 · ended succeeded · $1.30".
    private func runLine(_ run: RunInfo) -> String {
        var parts = ["▶ Run #\(run.id)"]
        parts.append((run.startedAt ?? run.queuedAt).formatted(date: .omitted, time: .shortened))
        parts.append(run.isLive ? run.state : "ended \(run.endWord)")
        parts.append(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "\(Fmt.tokens(run.tokens)) tok")
        return parts.joined(separator: " · ")
    }

    private var wakeName: String { model.agent(wakeTarget ?? key.agentID)?.name ?? "the agent" }

    /// "Woke Mira · comment · your message · 2m ago".
    private func wakeLine(_ wake: WakeNote) -> String {
        let who = model.agent(wake.agentID)?.name ?? "agent #\(wake.agentID)"
        let source = wake.source.replacingOccurrences(of: "_", with: " ")
        return [
            "Woke \(who)", source, wake.reason.isEmpty ? nil : String(wake.reason.prefix(80)),
            "\(Fmt.age(Date().timeIntervalSince(wake.at))) ago",
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var composer: some View {
        let name = agent?.name ?? "the agent"
        return AinkradComposer(
            text: $draft,
            placeholder: question != nil
                ? "Answer \(name)'s question — wakes \(name)" : "Message \(name) on \(issue?.key ?? "the issue")",
            isEditable: true, canSend: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            autoFocus: false, suggestions: { _ in [] }, onPick: { _, _ in }, onDrop: nil,
            onSend: {
                store.send(draft, on: key.issueID, waking: wakeTarget ?? key.agentID)
                draft = ""
            },
            chips: {
                if question != nil {
                    // Decision #44: the message answers the open question. A comment on the issue always does
                    // (the server's rule), so the target is shown, not clearable, here.
                    AinkradChip(label: "To: \(name)'s question", systemName: "arrowshape.turn.up.left")
                }
                // Whom the message wakes (API minor 14): the thread's agent unless you pick another.
                AinkradMenuButton(
                    items: model.agents.values.filter { $0.status == "active" }.sorted { $0.name < $1.name }.map {
                        agent in
                        AinkradMenuItem(title: agent.nameDotRole, systemName: nil) { wakeTarget = agent.id }
                    }
                ) { Text("Wakes \(wakeName)") }
            },
            leading: { EmptyView() },
            trailing: {
                Text("↵ sends and wakes \(wakeName) · ⇧↵ new line").citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.faint))
            }
        )
        .padding(.horizontal, skin.size.s20)
        .padding(.bottom, skin.size.s14)
    }
}

/// A centred system line in a conversation (a run started and how it ended).
private struct SystemLine: View {
    let text: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(text).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            .padding(.horizontal, skin.size.s12).padding(.vertical, skin.size.s4)
            .background(skin.color(skin.palette.white).opacity(skin.opacity.o05), in: Capsule())
            .frame(maxWidth: .infinity)
    }
}
