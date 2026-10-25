import AinkradAppKit
import SwiftUI

/// Screen 07: agent threads — one agent on one issue, the depth view (decision #9: the requirement thread is where
/// you talk; this is not an inbox). The list (All / Asks you / Unread) shows the agent, the issue, the last line,
/// and whether it waits on you (red when the last run died with no reply); the thread is the issue's comments with
/// the agent's runs between them, beside a context rail. Direct conversations (no issue) and "New" wait for the
/// server's agent messages.
struct ThreadsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: ThreadsPage { model.threadsPage }

    var body: some View {
        let threads = model.threads()
        let current = store.selectedThread.flatMap { key in threads.first { $0.key == key } } ?? threads.first
        HStack(spacing: 0) {
            list(threads, current: current?.key)
                .frame(width: skin.size.s320 + skin.size.s10)
                .background(skin.color(.palette("foreground", skin.opacity.o03)).opacity(skin.opacity.o60))
            Group {
                if let current {
                    ThreadDetail(store: store, model: model, thread: current).id(current.key)
                    ThreadRail(store: store, model: model, key: current.key).frame(width: skin.size.s300)
                } else {
                    AinkradEmptyState(
                        icon: "bubble.left", title: "No agent threads yet",
                        message: "A thread opens when an agent works an issue or asks you something on it."
                    )
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                }
            }
            .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: current?.key)
        }
        .offlineDimmed()
        .onChange(of: current?.key, initial: true) { _, key in
            guard let key else { return }
            store.openThread(key)
            page.seen[key] = Date()
        }
    }

    private func shown(_ threads: [ThreadSummary], _ filter: ThreadFilter) -> [ThreadSummary] {
        switch filter {
        case .all: threads
        case .asksYou: threads.filter(\.waitingOnYou)
        case .unread: threads.filter(page.isUnread)
        }
    }

    private func list(_ threads: [ThreadSummary], current: ThreadKey?) -> some View {
        let list = shown(threads, page.filter)
        return VStack(alignment: .leading, spacing: skin.size.s10) {
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text("Agent threads").citadelFont("t17", weight: "bold")
                    .foregroundStyle(skin.color(skin.text.primary))
                Text("\(Wording.count(threads.count, "thread")) · \(threads.filter(\.waitingOnYou).count) ask you")
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            .padding(.horizontal, skin.size.s4)
            .frame(height: skin.size.s34, alignment: .leading)
            AinkradGlideTabs(
                ThreadFilter.allCases.map {
                    AinkradGlideTab($0, title: $0.title, count: "\(shown(threads, $0).count)")
                },
                selection: Binding(get: { page.filter }, set: { page.filter = $0 }), height: skin.size.s32)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s8) {
                    ForEach(Array(list.enumerated()), id: \.element.id) { index, thread in
                        ThreadCard(
                            model: model, thread: thread, isSelected: thread.key == current,
                            isUnread: thread.key != current && page.isUnread(thread), index: index
                        ) { store.selectedThread = thread.key }
                    }
                    if list.isEmpty {
                        AinkradEmptyState(icon: "checkmark", title: "Nothing here", message: "")
                            .padding(.top, skin.size.s40)
                    }
                }
                .padding(skin.size.s2)
                .padding(.bottom, skin.size.s14)
            }
        }
        .padding(.top, skin.size.s14)
        .padding(.horizontal, skin.size.s12)
    }
}

/// A thread's accent (`thState`): red when its run died, amber when it waits on you, else the agent's state.
@MainActor
func threadState(_ thread: ThreadSummary, agent: AgentInfo?, skin: AinkradSkin) -> (Color, String) {
    if thread.died { return (skin.color(skin.palette.danger), "run lost") }
    if thread.waitingOnYou { return (skin.color(skin.palette.warning), "waiting on you") }
    switch agent?.figure {
    case .working?: return (skin.color(skin.palette.accentSecondary), "working")
    case .thinking?, .loading?: return (skin.color(skin.palette.accentViolet), "thinking")
    case .error?: return (skin.color(skin.palette.danger), "blocked")
    case .sleepy?, .rest?: return (skin.color(skin.text.muted), "asleep")
    default: return (skin.color(skin.text.muted), agent?.isPaused == true ? "paused" : "idle")
    }
}

/// A thread in the list (`.thc`): orb 38, name + ROLE, the unread dot or the age; the issue; the last line led by
/// the amber "asks you" or the red "run lost · no reply".
private struct ThreadCard: View {
    let model: CompanyModel
    let thread: ThreadSummary
    let isSelected: Bool
    let isUnread: Bool
    let index: Int
    let open: () -> Void
    @State private var hovering = false
    @State private var shown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let agent = model.agent(thread.key.agentID)
        let issue = model.issue(thread.key.issueID)
        let tint = threadState(thread, agent: agent, skin: skin).0
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        AinkradTapArea(action: open) {
            HStack(alignment: .top, spacing: skin.size.s11) {
                if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s38) }
                VStack(alignment: .leading, spacing: skin.size.s3) {
                    HStack(spacing: skin.size.s7) {
                        Text(agent?.name ?? "Agent").citadelFont("t12_5", weight: "semibold")
                            .foregroundStyle(skin.color(skin.text.primary))
                        Text((agent?.role ?? "").uppercased()).citadelFont("t10", weight: "semibold")
                            .tracking(skin.size.s1 / 2).foregroundStyle(skin.color(skin.text.faint))
                        Spacer(minLength: skin.size.s4)
                        if isUnread {
                            UnreadDot()
                        } else if thread.at > .distantPast {
                            Text(age).citadelFont("t10", mono: true)
                                .foregroundStyle(skin.color(skin.text.faint))
                        }
                    }
                    (Text(issue?.key ?? "#\(thread.key.issueID)").foregroundStyle(theme.accentSecondary)
                        + Text(" \(issue?.title ?? "")").foregroundStyle(skin.color(skin.text.primary)))
                        .citadelFont("t12_5", weight: "medium").lineLimit(1)
                    HStack(spacing: skin.size.s6) {
                        if thread.waitingOnYou {
                            AsksBadge(count: 1, text: "asks you")
                        } else if thread.died {
                            Text("run lost · no reply").citadelFont("t10_5").foregroundStyle(status.danger).fixedSize()
                        }
                        Text(lastLine(agent)).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                            .lineLimit(1).opacity(thread.died && thread.lastLine.hasPrefix("run ended") ? 0 : 1)
                    }
                }
            }
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s11)
            .background(
                shape.fill(
                    isSelected
                        ? tint.opacity(skin.opacity.o09)
                        : skin.color(.palette("foreground", hovering ? skin.opacity.o06 : skin.opacity.o03)))
            )
            .overlay(alignment: .leading) { if isSelected { Rectangle().fill(tint).frame(width: skin.size.s3) } }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isSelected ? tint.opacity(skin.opacity.o40) : skin.color(.palette("foreground", skin.opacity.o06)),
                    lineWidth: 1)
            )
            .contentShape(shape)
        }
        .opacity(shown ? 1 : 0)
        .offset(x: hovering && !reduceMotion ? skin.size.s2 : 0, y: shown || reduceMotion ? 0 : skin.size.s8)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .onAppear {
            withAnimation(
                reduceMotion
                    ? nil
                    : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.35)).delay(
                        Double(index) * 0.04)
            ) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }

    /// The last line without the agent's own name ("Quill: …" → "…"); yours keeps "You: ".
    private func lastLine(_ agent: AgentInfo?) -> String {
        guard let name = agent?.name, thread.lastLine.hasPrefix("\(name): ") else { return thread.lastLine }
        return String(thread.lastLine.dropFirst(name.count + 2))
    }

    /// "now" under a minute — the prototype's thread list never counts seconds up in the list — else the shared word.
    private var age: String {
        let seconds = Date().timeIntervalSince(thread.at)
        return seconds < 60 ? "now" : Fmt.age(seconds)
    }
}

/// The blue unread dot with its glow and pulse.
private struct UnreadDot: View {
    @State private var dim = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let blue = skin.color(skin.palette.accentPrimary)
        Circle().fill(blue).frame(width: skin.size.s8, height: skin.size.s8)
            .shadow(color: blue, radius: skin.size.s5)
            .opacity(dim ? skin.opacity.o35 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 0.8)).repeatForever(
                        autoreverses: true)
                ) { dim = true }
            }
    }
}
