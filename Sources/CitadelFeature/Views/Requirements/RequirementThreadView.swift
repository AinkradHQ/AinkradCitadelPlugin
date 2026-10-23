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
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: RequirementsPage { model.requirementsPage }
    private var thread: RequirementThread? { page.threads[requirement.id] }
    private var plan: PlanTree? { page.plans[requirement.id] }
    private var target: ComposerTarget {
        thread?.target(cleared: page.targetCleared) ?? .owner(agentID: requirement.ownerAgentID)
    }
    private var ownerName: String { model.ownerName(thread?.ownerAgentID ?? requirement.ownerAgentID) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "\(requirement.key) \(requirement.title)", crumb: crumb) {
                HStack(spacing: skin.size.s8) {
                    AinkradIconButton(
                        systemName: "doc.text", size: skin.size.s30, tooltip: "Artifacts of \(requirement.key)"
                    ) { store.showArtifacts(requirement: requirement.id) }
                    .outlineBox()
                    AinkradIconButton(
                        systemName: "envelope", size: skin.size.s30, tooltip: "Agent threads on \(requirement.key)"
                    ) { store.screen = .threads }
                    .outlineBox()
                    AinkradMenuButton(items: [
                        AinkradMenuItem(title: "Rename…", systemName: "pencil") { renaming = true },
                        AinkradMenuItem(title: "Cancel requirement…", systemName: "xmark.circle", isDestructive: true) {
                            cancelling = true
                        },
                    ]) {
                        Image(systemName: "ellipsis")
                    }
                    .disabled(["done", "cancelled"].contains(requirement.state))
                }
            }
            conversation
            composer
        }
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

    /// "Citadel · with Aldric (CEO) · IN PROGRESS".
    private var crumb: Text {
        let muted = skin.color(skin.text.muted)
        let projects = Set(plan?.epics.map(\.projectID) ?? [])
        let project = model.projects.first { projects.contains($0.id) }?.name
        var parts = [project, "with \(ownerName)"].compactMap { $0 }
        if requirement.state == "planning" { parts.append("planning, no work yet") }
        let state = requirement.state.replacingOccurrences(of: "_", with: " ")
        return Text(parts.joined(separator: " · ") + " · ").foregroundStyle(muted)
            + Text(skin.labelCased(state)).foregroundStyle(theme.accentSecondary)
    }

    private var conversation: some View {
        let lines = HubLine.lines(thread?.items ?? [])
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: skin.size.s14) {
                    if thread != nil, lines.isEmpty {
                        Text("Nothing here yet. Tell \(ownerName) what you want.").citadelFont("t12")
                            .foregroundStyle(skin.color(skin.text.faint)).frame(maxWidth: .infinity)
                    }
                    ForEach(lines) { line in
                        lineView(line).transition(
                            reduceMotion ? .opacity : .opacity.combined(with: .offset(y: skin.size.s6)))
                    }
                    Color.clear.frame(height: skin.size.s1).id("end")
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.vertical, skin.size.s10)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: lines.map(\.id))
            }
            .onChange(of: lines.count, initial: true) { _, _ in proxy.scrollTo("end", anchor: .bottom) }
        }
    }

    @ViewBuilder private func lineView(_ line: HubLine) -> some View {
        switch line {
        case .artifacts(let list):
            ArtifactPair(store: store, model: model, artifacts: list).padding(.leading, skin.size.s40)
        case .item(.message(let comment, let at)):
            message(comment, at: at)
        case .item(.question(let question, let answer)):
            if question.isOpen {
                questionCard(question)
            } else {
                Receipt(model: model, question: question, answer: answer)
            }
        case .item(.approval(let approval, let at)):
            ThreadApprovalCard(store: store, model: model, approval: approval, at: at).padding(.leading, skin.size.s40)
        case .item(.artifact(let artifact)):
            ArtifactPair(store: store, model: model, artifacts: [artifact]).padding(.leading, skin.size.s40)
        }
    }

    @ViewBuilder private func message(_ comment: CommentInfo, at: Date) -> some View {
        if let author = model.agent(comment.agentID) {
            let role = author.orgRole == "ceo" ? "CEO" : author.role
            let on = comment.issueID == plan?.intakeIssueID ? nil : model.issue(comment.issueID).map { "on \($0.key)" }
            AinkradChatBubble(
                text: comment.body, role: .agent, author: author.name,
                meta: [role, on, Self.time(at)].compactMap { $0 }.joined(separator: " · ")
            ) { AgentFigure(agent: author, model: model, size: skin.size.s28) }
        } else {
            AinkradChatBubble(text: comment.body, role: .user, author: "You", meta: Self.time(at))
        }
    }

    private func questionCard(_ question: QuestionInfo) -> some View {
        let asker = model.agent(question.agentID)
        let run = question.runID.flatMap { model.runs[$0] }
        let context = run.map { $0.isLive ? "its run waits on you" : "while planning" }
        return AinkradQuestionCard(
            asker: model.askerName(question.agentID), issueKey: question.issueKey, context: context,
            age: Fmt.age(Date().timeIntervalSince(question.askedAt)), question: question.text,
            replies: question.options, route: route(question),
            onReply: { store.send($0, requirement: requirement.id, to: .question(question)) }
        ) {
            if let asker { AgentFigure(agent: asker, model: model, size: skin.size.s18) }
        }
    }

    private func route(_ question: QuestionInfo) -> String {
        let name = model.agent(question.agentID)?.name ?? "the agent"
        let owner = model.ownerWord(thread?.ownerAgentID ?? requirement.ownerAgentID)
        return "Your answer goes to \(name) on \(question.issueKey) and wakes it — not to the \(owner)"
    }

    private var composer: some View {
        let send = {
            store.send(draft, requirement: requirement.id, to: target)
            draft = ""
        }
        return AinkradComposer(
            text: $draft, placeholder: placeholder, isEditable: true,
            canSend: !draft.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty, autoFocus: false,
            suggestions: { _ in [] }, onPick: { _, _ in }, onDrop: nil, onSend: send,
            chips: { targetRow },
            leading: {
                Text(hint).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            },
            trailing: {
                AinkradIconButton(
                    systemName: "paperclip", size: AinkradComposer<EmptyView, EmptyView, EmptyView>.controlHeight,
                    tooltip: "Attach a file"
                ) { attach() }
                .outlineBox()
            }
        )
        .padding(.horizontal, skin.size.s20)
        .padding(.bottom, skin.size.s14)
    }

    private var placeholder: String {
        switch target {
        case .question(let q): "Answer \(model.agent(q.agentID)?.name ?? "the agent") — wakes it on \(q.issueKey)"
        case .owner: "Message \(ownerName)"
        }
    }

    /// "↵ answers Kestrel · ⇧↵ new line".
    private var hint: String {
        switch target {
        case .question(let q): "↵ answers \(model.agent(q.agentID)?.name ?? "the agent") · ⇧↵ new line"
        case .owner: "↵ sends to \(ownerName) · ⇧↵ new line"
        }
    }

    /// "To [Kestrel · CIT-62 question ✕] — clear to talk to Aldric (CEO)".
    private var targetRow: some View {
        HStack(spacing: skin.size.s6) {
            Text("To").citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
            switch target {
            case .question(let q):
                AinkradChip(
                    label: "\(model.agent(q.agentID)?.name ?? "Agent") · \(q.issueKey) question",
                    systemName: "questionmark.circle", onRemove: { page.targetCleared = true }
                )
                .fixedSize()
                Text("— clear to talk to \(ownerName)").citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.faint))
            case .owner:
                AinkradChip(label: ownerName, systemName: "person")
                if page.targetCleared, !(thread?.openQuestions.isEmpty ?? true) {
                    AinkradButton(title: "Answer the open question", style: .ghost) { page.targetCleared = false }
                        .borderless().secondaryAccent().compact().fixedSize()
                }
            }
        }
    }

    /// `09:31` today, `Mon 09:12` this week, `Oct 19` before.
    static func time(_ date: Date, now: Date = Date()) -> String {
        let calendar = Calendar.current
        if calendar.isDate(date, inSameDayAs: now) { return date.formatted(.dateTime.hour().minute()) }
        if now.timeIntervalSince(date) < 6 * 86_400 {
            return date.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        }
        return date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// An answered question, collapsed to one line: "Wren on CIT-58 asked "…" — you: yes, end them · routed to Wren".
private struct Receipt: View {
    let model: CompanyModel
    let question: QuestionInfo
    let answer: String?
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let asker = model.agent(question.agentID)
        let name = asker?.name ?? "Agent"
        let primary = skin.color(skin.text.primary)
        let muted = skin.color(skin.text.muted)
        HStack(spacing: skin.size.s8) {
            Text("↩").citadelFont("t12").foregroundStyle(status.success)
            if let asker { AgentFigure(agent: asker, model: model, size: skin.size.s18) }
            (Text(name).foregroundStyle(primary).fontWeight(.medium) + Text(" on ").foregroundStyle(muted)
                + Text(question.issueKey).foregroundStyle(theme.accentSecondary)
                + Text(" asked \"\(question.text)\"").foregroundStyle(muted)
                + Text(answer == nil ? "" : " — you: ").foregroundStyle(muted)
                + Text(answer ?? "").foregroundStyle(primary).fontWeight(.medium))
                .citadelFont("t12").lineLimit(2)
            Spacer(minLength: skin.size.s8)
            Text(question.state == "cancelled" ? "withdrawn" : "routed to \(name) · done").citadelFont("t11")
                .foregroundStyle(skin.color(skin.text.faint)).fixedSize()
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s7)
        .background(
            skin.color(skin.palette.white).opacity(hovering ? skin.opacity.o06 : skin.opacity.o03),
            in: RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous)
        )
        .onHover { hovering = $0 }
        .accessibilityElement(children: .combine)
    }
}
