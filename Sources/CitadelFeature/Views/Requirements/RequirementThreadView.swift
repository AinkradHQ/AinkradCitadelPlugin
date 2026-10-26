import AinkradAppKit
import SwiftUI

/// The requirement's thread with its owner: your messages, the owner's replies, plan approvals, QA + merge cards,
/// artifacts, and every agent's question as an amber card. The composer answers the newest open question (its To
/// chip) and the route line says who is woken; clearing the chip talks to the owner (decisions #44, #45).
struct RequirementThreadView: View {
    let store: CitadelStore
    let model: CompanyModel
    let requirement: RequirementInfo
    @State private var draft = ""
    @State private var renaming = false
    @State private var cancelling = false
    /// You sent a message; the agent it went to shows typing until the thread moves.
    @State private var awaiting: Int64?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: RequirementsPage { model.requirementsPage }
    private var thread: RequirementThread? { page.threads[requirement.id] }
    private var plan: PlanTree? { page.plans[requirement.id] }
    private var target: ComposerTarget {
        thread?.target(cleared: page.targetCleared) ?? .owner(agentID: requirement.ownerAgentID)
    }
    private var owner: AgentInfo? { model.agent(thread?.ownerAgentID ?? requirement.ownerAgentID) ?? model.ceo }
    private var ownerName: String { owner?.name ?? "the CEO" }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            RequirementHero(
                store: store, model: model, requirement: requirement, renaming: $renaming, cancelling: $cancelling)
            if page.askingChanges, requirement.state == "plan_review" {
                AskForChangesPanel(store: store, model: model, requirement: requirement)
                    .transition(.opacity.combined(with: .offset(y: -skin.size.s6)))
            }
            conversation
            composer
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: page.askingChanges)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .ainkradSheet(isPresented: $renaming) {
            PromptSheet(
                title: "Rename \(requirement.key)", message: "The thread, the plan and its issues keep their keys.",
                placeholder: "Title", confirmTitle: "Rename", text: requirement.title, isPresented: $renaming
            ) { store.rename(requirement: requirement, to: $0) }
        }
        .ainkradSheet(isPresented: $cancelling) {
            PromptSheet(
                title: "Cancel \(requirement.key)?",
                message:
                    "Its open issues are cancelled with it. Citadel refuses while a run works on one — stop the run first.",
                placeholder: "Why (optional)", confirmTitle: "Cancel requirement", isDestructive: true,
                allowsEmpty: true, text: "", isPresented: $cancelling
            ) { store.cancel(requirement: requirement, reason: $0) }
        }
    }

    /// 📎: pick a file; it lands in the thread as an artifact card.
    private func attach() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.message = "Attach a file to \(requirement.key)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        store.attach(url, requirement: requirement)
    }

    /// "▶ Work started · 4 agents" after the approved plan; "✓ Done · 21 pts" once closed.
    private var lines: [HubLine] {
        let agents = Set(plan?.allTasks.compactMap(\.assigneeAgentID) ?? []).count
        let started = requirement.state == "planning" ? nil : "▶ Work started · \(Wording.count(agents, "agent"))"
        let closed = requirement.state == "done" ? "✓ Done · \(requirement.points) pts" : nil
        return HubLine.lines(thread?.items ?? [], started: agents > 0 ? started : nil, closed: closed)
    }

    /// The owner drafting the plan (a live run while planning), or the agent you just wrote to.
    private var typing: (agent: AgentInfo, note: String)? {
        if let awaiting, let agent = model.agent(awaiting) { return (agent, "typing…") }
        guard requirement.state == "planning", let owner,
            model.runs.values.contains(where: { $0.agentID == owner.id && $0.isLive })
        else { return nil }
        return (owner, "\(owner.name) is drafting the plan…")
    }

    private var conversation: some View {
        let lines = lines
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: skin.size.s16) {
                    if thread != nil, lines.isEmpty, typing == nil {
                        Text("Nothing here yet. Tell \(ownerName) what you want.").citadelFont("t12")
                            .foregroundStyle(skin.color(skin.text.faint)).frame(maxWidth: .infinity)
                    }
                    if thread == nil {
                        AinkradSkeletonRow(widthFraction: 0.8, showsAvatar: true).ainkradShimmer()
                        AinkradSkeletonRow(widthFraction: 0.6, showsAvatar: true).ainkradShimmer()
                        AinkradSkeletonRow(widthFraction: 0.7, showsAvatar: true).ainkradShimmer()
                    }
                    ForEach(lines) { line in
                        lineView(line).transition(
                            reduceMotion ? .opacity : .opacity.combined(with: .offset(y: skin.size.s8)))
                    }
                    if let typing {
                        TypingTurn(agent: typing.agent, model: model, note: typing.note).transition(.opacity)
                    }
                    Color.clear.frame(height: skin.size.s1).id("end")
                }
                .padding(.horizontal, skin.size.s22)
                .padding(.top, skin.size.s10)
                .padding(.bottom, skin.size.s18)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: lines.map(\.id))
            }
            .onChange(of: lines.count, initial: true) { _, _ in
                awaiting = nil
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

    @ViewBuilder private func lineView(_ line: HubLine) -> some View {
        switch line {
        case .artifacts(let list):
            ArtifactTiles(store: store, model: model, artifacts: list).padding(.leading, skin.size.s42)
        case .permissions(let list):
            PermissionsReceipt(approvals: list).padding(.leading, skin.size.s42)
        case .system(let text):
            SysLine(text: text)
        case .item(.message(let comment, let at)):
            message(comment, at: at)
        case .item(.question(let question, let answer)):
            if question.isOpen {
                AskCard(store: store, model: model, question: question, requirement: requirement.id)
            } else {
                answered(question, answer: answer).padding(.leading, skin.size.s42)
            }
        case .item(.approval(let approval, let at)):
            ThreadApprovalCard(store: store, model: model, requirement: requirement, approval: approval, at: at)
                .padding(.leading, skin.size.s42)
        case .item(.artifact(let artifact)):
            ArtifactTiles(store: store, model: model, artifacts: [artifact]).padding(.leading, skin.size.s42)
        }
    }

    @ViewBuilder private func message(_ comment: CommentInfo, at: Date) -> some View {
        if let author = model.agent(comment.agentID) {
            let role = author.roleLabel
            // "on CIT-61" for a plan task's issue; the intake issue is the thread itself.
            let key =
                plan?.allTasks.contains { $0.issueID == comment.issueID } == true
                ? model.issue(comment.issueID)?.key : nil
            AgentTurn(
                agent: author, model: model, role: role, issueKey: key, at: Self.time(at), text: comment.body,
                onKey: key == nil ? nil : { model.requirementsPage.openItem(comment.issueID) })
        } else {
            YouTurn(text: comment.body, at: Self.time(at))
        }
    }

    /// "↩ ● Wren asked "…" — you: yes, end them        routed · done".
    private func answered(_ question: QuestionInfo, answer: String?) -> some View {
        let asker = model.agent(question.agentID)
        let primary = skin.color(skin.text.primary)
        return ReceiptRow(glyph: "↩", trailing: question.state == "cancelled" ? "withdrawn" : "routed · done") {
            if let asker { AgentFigure(agent: asker, model: model, size: skin.size.s20) }
            (Text(asker?.name ?? "Agent").foregroundStyle(primary).fontWeight(.medium)
                + Text(" asked “\(question.text)”") + Text(answer == nil ? "" : " — you: ")
                + Text(answer ?? "").foregroundStyle(primary).fontWeight(.medium))
                .lineLimit(1)
        }
    }

    private var composer: some View {
        let asker: AgentInfo? = if case .question(let q) = target { model.agent(q.agentID) } else { nil }
        return AinkradConversationComposer(
            text: $draft, placeholder: placeholder, isTargeted: asker != nil, hint: hint, onAttach: attach,
            onSend: send,
            toRow: {
                if case .question(let q) = target, let asker {
                    HStack(spacing: skin.size.s8) {
                        Text("To").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                        AinkradComposerChip(label: "\(asker.name) · \(q.issueKey) question") {
                            page.targetCleared = true
                        } avatar: {
                            AgentFigure(agent: asker, model: model, size: skin.size.s18)
                        }
                        Text("your answer wakes \(asker.name), not the \(model.ownerWord(requirement.ownerAgentID))")
                            .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    }
                } else if page.targetCleared, let open = thread?.openQuestions.first {
                    AinkradButton(
                        title: model.agent(open.agentID).map { "Answer \($0.name)'s question" }
                            ?? "Answer the question",
                        style: .ghost
                    ) {
                        page.targetCleared = false
                    }
                    .borderless().secondaryAccent().compact().fixedSize()
                }
            },
            avatar: {
                if let speaker = asker ?? owner { AgentFigure(agent: speaker, model: model, size: skin.size.s28) }
            }
        )
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.size.s14)
    }

    private func send() {
        let text = draft
        draft = ""
        if case .question(let q) = target {
            store.answer(text, question: q, requirement: requirement.id)
            awaiting = q.agentID
        } else {
            store.send(text, requirement: requirement.id, to: target)
            awaiting = owner?.id
        }
    }

    private var placeholder: String {
        switch target {
        case .question(let q): "Answer \(model.agent(q.agentID)?.name ?? "the agent")…"
        case .owner: "Message \(ownerName) about \(requirement.key)…"
        }
    }

    /// "↵ answers Kestrel · ⇧↵ new line · @ adds an agent".
    private var hint: String {
        switch target {
        case .question(let q):
            "↵ answers \(model.agent(q.agentID)?.name ?? "the agent") · ⇧↵ new line · @ adds an agent"
        case .owner: "↵ sends to \(ownerName) · ⇧↵ new line · @ adds an agent"
        }
    }

    /// `Today 09:31`, `Mon 09:12` this week, `Oct 19` before — 24-hour, like the rest of Citadel.
    static func time(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return "Today \(Fmt.clock(date))" }
        if now.timeIntervalSince(date) < 6 * 86_400 {
            return "\(date.formatted(.dateTime.weekday(.abbreviated))) \(Fmt.clock(date))"
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}
