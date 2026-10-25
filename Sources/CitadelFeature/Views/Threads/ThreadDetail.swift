import AinkradAppKit
import SwiftUI

/// One thread (`#/chat/:agent`): the hero (agent tile, crumb, the issue, state / agent / model / requirement / live
/// run chips and the dock), the hub banner when the open question is also in a requirement thread, the transcript,
/// and the composer — which posts a comment that answers the open question (decision #44's auto-target) and wakes
/// the agent. Comments carry no timestamps yet (the server's `Comment` has no `created_at`).
struct ThreadDetail: View {
    let store: CitadelStore
    let model: CompanyModel
    let thread: ThreadSummary
    @State private var draft = ""
    /// The agent the message wakes; `nil` is the thread's own agent.
    @State private var wakeTarget: Int64?
    /// You sent a message: the agent shows typing until the thread moves.
    @State private var awaiting = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var key: ThreadKey { thread.key }
    private var agent: AgentInfo? { model.agent(key.agentID) }
    private var issue: IssueInfo? { model.issue(key.issueID) }
    private var question: QuestionInfo? { model.openQuestion(key) }
    private var requirement: RequirementInfo? {
        issue?.requirementID.flatMap { id in model.requirements.first { $0.id == id } }
    }
    private var liveRun: RunInfo? {
        model.runs.values.filter { $0.agentID == key.agentID && $0.isLive }.max { $0.queuedAt < $1.queuedAt }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
            if let question, let requirement, question.requirementID == requirement.id { hub(requirement) }
            transcript
            composer
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private func openRequirement(_ requirement: RequirementInfo) {
        model.requirementsPage.selectedID = requirement.id
        store.screen = .requirements
    }

    private var hero: some View {
        let palette = agent?.palette ?? .neonTide
        let (ca, cb) = (palette.lightColor, palette.deepColor)
        let (tint, word) = threadState(thread, agent: agent, skin: skin)
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        return VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(alignment: .center, spacing: skin.size.s16) {
                if let agent {
                    AgentFigure(agent: agent, model: model, size: skin.size.s56 + skin.size.s2)
                        .frame(width: skin.size.s64, height: skin.size.s64)
                        .background(
                            skin.color(.palette("black", skin.opacity.o18)),
                            in: RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous))
                }
                VStack(alignment: .leading, spacing: skin.size.s3) {
                    Text("Agent threads  ›  \(issue?.key ?? "Direct")").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                    HStack(alignment: .firstTextBaseline, spacing: skin.size.s10) {
                        Text(issue?.key ?? "").citadelFont("t12", mono: true).foregroundStyle(theme.accentSecondary)
                        Text(issue?.title ?? agent?.nameDotRoleLabel ?? "").citadelFont("t20", weight: "bold")
                            .lineLimit(1)
                            .foregroundStyle(skin.color(skin.text.primary))
                    }
                    AinkradFlowLayout(spacing: skin.size.s6) {
                        GlowStatePill(text: word, tint: tint)
                        if let agent {
                            ThreadHeroChip(action: { store.open(.agent(agent.id)) }) {
                                AgentFigure(agent: agent, model: model, size: skin.size.s16)
                                Text(agent.nameDotRoleLabel)
                            }
                            ThreadHeroChip {
                                Text("\(AgentLook.harnessName(agent.harness)) ·")
                                Text(agent.model).citadelFont("t11", mono: true)
                            }
                        }
                        if let requirement {
                            ThreadHeroChip(action: { openRequirement(requirement) }) {
                                Text(requirement.key).citadelFont("t11", mono: true).foregroundStyle(
                                    theme.accentSecondary)
                                Text(requirement.title).lineLimit(1)
                            }
                        }
                        if let run = liveRun {
                            ThreadHeroChip(action: { store.open(.run(run.id)) }) {
                                Circle().fill(theme.accentSecondary).frame(width: skin.size.s6, height: skin.size.s6)
                                Text(
                                    "run #\(run.id) · \(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "\(Fmt.tokens(run.tokens)) tok")"
                                )
                            }
                        }
                    }
                    .padding(.top, skin.size.s5)
                }
            }
            AinkradFlowLayout(spacing: skin.size.s6) {
                if let requirement {
                    AinkradDockButton("Open \(requirement.key)", systemImage: "text.alignleft") {
                        openRequirement(requirement)
                    }
                }
                if let run = liveRun {
                    AinkradDockButton("Watch run", systemImage: "play") { store.open(.run(run.id)) }
                }
                if let agent {
                    AinkradDockButton("Agent profile", systemImage: "person.crop.circle") {
                        store.open(.agent(agent.id))
                    }
                }
            }
        }
        .padding(.horizontal, skin.size.s18)
        .padding(.vertical, skin.size.s16)
        .background(
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: ca.opacity(skin.opacity.o18), location: 0), .init(color: .clear, location: 0.6),
                        .init(color: cb.opacity(skin.opacity.o14), location: 1),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
            )
            .background(shape.fill(skin.color(.palette("background", skin.opacity.o88))))
        )
        .overlay(shape.strokeBorder(ca.opacity(skin.opacity.o30), lineWidth: 1))
        .padding(.horizontal, skin.size.s14)
        .padding(.top, skin.size.s14)
        .padding(.bottom, skin.size.s6)
    }

    /// `.th-hub`: "Quill's question also appears in R-10 · …. Answer here or there — both clear."
    private func hub(_ requirement: RequirementInfo) -> some View {
        let blue = skin.color(skin.palette.accentPrimary)
        return HStack(spacing: skin.size.s10) {
            Image(systemName: "link").citadelFont("t12").foregroundStyle(blue)
                .frame(width: skin.size.s26, height: skin.size.s26)
                .background(blue.opacity(skin.opacity.o16), in: RoundedRectangle(cornerRadius: skin.size.s8))
            (Text("\(agent?.name ?? "The agent")'s question also appears in ")
                + Text("\(requirement.key) · \(requirement.title)").foregroundStyle(skin.color(skin.text.primary))
                .bold()
                + Text(". Answer here or there — both clear."))
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted)).lineLimit(2)
            Spacer(minLength: skin.size.s8)
            AinkradButton(title: "Open \(requirement.key) ›", style: .ghost) { openRequirement(requirement) }
                .borderless().secondaryAccent().compact().fixedSize()
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s8)
        .background(blue.opacity(skin.opacity.o08), in: RoundedRectangle(cornerRadius: skin.size.s12))
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s12).strokeBorder(blue.opacity(skin.opacity.o18), lineWidth: 1)
        )
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.size.s4)
    }

    private var transcript: some View {
        let lines = model.conversation(key)
        return ScrollViewReader { proxy in
            ScrollView {
                LazyVStack(alignment: .leading, spacing: skin.size.s16) {
                    if lines.isEmpty, let agent {
                        VStack(spacing: skin.size.s8) {
                            AgentFigure(agent: agent, model: model, size: skin.size.s72)
                            Text("Start a conversation with \(agent.name)").citadelFont("t14", weight: "semibold")
                                .foregroundStyle(skin.color(skin.text.primary))
                            Text("Your message lands on \(issue?.key ?? "the issue") and wakes \(agent.name).")
                                .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.top, skin.size.s60)
                    }
                    ForEach(lines) { line in
                        lineView(line).transition(
                            reduceMotion ? .opacity : .opacity.combined(with: .offset(y: skin.size.s14)))
                    }
                    if let wake = model.wakes[key.issueID]?.last { SysLine(text: wakeLine(wake)) }
                    if awaiting, let agent { TypingTurn(agent: agent, model: model, note: "typing…") }
                    Color.clear.frame(height: skin.size.s1).id("end")
                }
                .padding(.horizontal, skin.size.s22)
                .padding(.top, skin.size.s10)
                .padding(.bottom, skin.size.s18)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: lines.map(\.id))
            }
            .onChange(of: lines.count, initial: true) { _, _ in
                awaiting = false
                proxy.scrollTo("end", anchor: .bottom)
            }
        }
    }

    @ViewBuilder private func lineView(_ line: ThreadLine) -> some View {
        switch line {
        case .comment(let comment):
            if let author = comment.agentID.flatMap({ model.agent($0) }) {
                let docs = comment.runID.map { run in model.artifactsPage.items.filter { $0.runID == run } } ?? []
                AgentTurn(agent: author, model: model, text: comment.body) {
                    if !docs.isEmpty {
                        ArtifactTiles(store: store, model: model, artifacts: docs, open: openArtifact)
                    }
                }
            } else {
                YouTurn(text: comment.body, at: nil)
            }
        case .run(let run):
            SysLine(text: runLine(run, died: run.died), tint: run.died ? status.danger : nil) {
                store.open(.run(run.id))
            }
        case .question(let question):
            if let asker = model.agent(question.agentID) {
                AgentTurn(agent: asker, model: model, text: question.text) {
                    if question.isOpen, !question.options.isEmpty {
                        QuickReplies(options: question.options) { send($0) }
                    }
                }
            }
        }
    }

    private func openArtifact(_ artifact: ArtifactInfo) {
        model.artifactsPage.selectedID = artifact.id
        store.screen = .artifacts
    }

    /// "▶ Run #422 · 11:14 · ended succeeded · $1.30"; a died one leads with ⚠.
    private func runLine(_ run: RunInfo, died: Bool) -> String {
        var parts = ["\(died ? "⚠" : "▶") Run #\(run.id)"]
        parts.append(Fmt.clock(run.startedAt ?? run.queuedAt))
        parts.append(run.isLive ? run.state : "ended \(run.endWord)")
        parts.append(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "\(Fmt.tokens(run.tokens)) tok")
        return parts.joined(separator: " · ")
    }

    /// "Woke Mira · comment · your message · 2m ago".
    private func wakeLine(_ wake: WakeNote) -> String {
        let who = model.agent(wake.agentID)?.name ?? "agent #\(wake.agentID)"
        return [
            "Woke \(who)", wake.source.replacingOccurrences(of: "_", with: " "),
            wake.reason.isEmpty ? nil : String(wake.reason.prefix(80)),
            "\(Fmt.age(Date().timeIntervalSince(wake.at))) ago",
        ].compactMap { $0 }.joined(separator: " · ")
    }

    private var wakeName: String { model.agent(wakeTarget ?? key.agentID)?.name ?? "the agent" }

    private func send(_ text: String) {
        store.send(text, on: key.issueID, waking: wakeTarget ?? key.agentID)
        awaiting = true
    }

    private var composer: some View {
        let name = agent?.name ?? "the agent"
        return ConversationComposer(
            text: $draft, placeholder: question != nil ? "Answer \(name)…" : "Message \(name)…",
            isTargeted: question != nil, hint: "↵ sends and wakes \(wakeName) · @ adds another agent · ⇧↵ new line",
            onSend: {
                send(draft)
                draft = ""
            },
            toRow: {
                // Whom the message wakes (API minor 14): the thread's agent unless you pick another.
                HStack(spacing: skin.size.s8) {
                    Text("Wakes").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    AinkradMenuButton(
                        items: model.agents.values.filter { $0.status == "active" }.sorted { $0.name < $1.name }.map {
                            agent in
                            AinkradMenuItem(title: agent.nameDotRoleLabel, systemName: nil) { wakeTarget = agent.id }
                        }
                    ) {
                        ComposerToChip(label: wakeChip, onRemove: nil) {
                            if let who = model.agent(wakeTarget ?? key.agentID) {
                                AgentFigure(agent: who, model: model, size: skin.size.s18)
                            }
                        }
                    }
                    .help("Choose whom your message wakes")
                }
            },
            avatar: { if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s28) } }
        )
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.size.s14)
    }

    private var wakeChip: String {
        let who = model.agent(wakeTarget ?? key.agentID)
        let base = who.map { $0.nameDotRoleLabel } ?? "Agent"
        return question != nil && wakeTarget == nil ? "\(base) · \(issue?.key ?? "") question" : base
    }
}
