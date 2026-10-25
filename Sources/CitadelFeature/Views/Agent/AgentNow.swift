import AinkradAppKit
import SwiftUI

/// Now, live: pulse, the issue, a log of the run's last tool calls with the current one blinking, tokens against
/// the per-run cap, and the approval it waits on.
struct LiveNow: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    let run: RunInfo
    @State private var caret = true
    @State private var ping = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let issue = model.issue(run.issueID)
        let calls = Transcript.items(model.transcripts[run.id] ?? [], runState: run.state).compactMap {
            item -> ToolCallItem? in
            if case .tool(let call) = item { return call }
            return nil
        }
        let done = calls.filter { $0.status != .running && $0.status != .waiting }.suffix(5)
        let now = model.toolNow[run.id] ?? calls.last.map { "\($0.name) \($0.argument)" } ?? "starting"
        let cyan = skin.color(skin.palette.accentSecondary)
        let approval = model.waitingApproval(run: run.id)
        BentoBox(live: true, onTap: { store.open(.run(run.id)) }) {
            HStack(spacing: skin.size.s8) {
                Circle().fill(cyan).frame(width: skin.size.s8, height: skin.size.s8)
                    .background(
                        Circle().stroke(cyan.opacity(ping ? 0 : skin.opacity.o50), lineWidth: skin.size.s2)
                            .scaleEffect(ping ? 3 : 1))
                Text("Now").citadelFont("t10_5", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
                if let issue { Text(issue.key).citadelFont("t11", mono: true).foregroundStyle(cyan) }
                Text(issue?.title ?? "run #\(run.id)").citadelFont("t13", weight: "semibold").lineLimit(1)
                Spacer(minLength: skin.size.s4)
                Text(Fmt.duration(Date().timeIntervalSince(run.startedAt ?? run.queuedAt))).citadelFont(
                    "t11", mono: true
                )
                .foregroundStyle(skin.color(skin.text.faint))
            }
            VStack(alignment: .leading, spacing: skin.size.s6) {
                HStack {
                    Text("\(AgentLook.harnessName(run.harness)) · \(run.model ?? agent.model)")
                    Spacer()
                    Text("run #\(run.id)")
                }
                .citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
                Spacer(minLength: skin.size.s8)
                ForEach(Array(done.enumerated()), id: \.element.id) { _, call in
                    HStack(spacing: skin.size.s8) {
                        Text(call.status == .failed ? "✕" : "✓")
                            .foregroundStyle(
                                call.status == .failed
                                    ? skin.color(skin.palette.danger) : skin.color(skin.palette.success)
                            )
                            .frame(width: skin.size.s12)
                        Text("\(call.name) \(call.argument)").lineLimit(1).truncationMode(.middle)
                    }
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(spacing: skin.size.s2) {
                    Text("▸ \(now)").foregroundStyle(cyan).lineLimit(1).truncationMode(.middle)
                    Text("▍").foregroundStyle(cyan).opacity(caret ? 1 : 0)
                }
            }
            .citadelFont("t12", mono: true)
            .foregroundStyle(skin.color(skin.text.muted))
            .padding(skin.size.s12)
            .frame(maxWidth: .infinity, minHeight: skin.size.s150, maxHeight: .infinity, alignment: .topLeading)
            .background(
                skin.color(.palette("black", skin.opacity.o28)), in: RoundedRectangle(cornerRadius: skin.size.s12))
            HStack(spacing: skin.size.s10) {
                MiniBar(fraction: Double(run.tokens) / Double(max(model.runCap ?? run.tokens, 1)))
                Text(
                    "\(Fmt.tokens(run.tokens)) tok · \(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "unpriced")"
                )
                .citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
            }
            if let approval {
                HStack(spacing: skin.size.s8) {
                    Text("⌁").foregroundStyle(skin.color(skin.palette.warning))
                    Text(model.summary(approval).title).lineLimit(1)
                    Spacer()
                    AinkradButton(title: "Review", style: .secondary) {
                        store.selectedApproval = approval.id
                        store.screen = .approvals
                        store.detail = nil
                    }
                    .compact().fixedSize()
                    AinkradButton(title: approval.kind == "budget_overrun" ? "Raise" : "Allow once") {
                        store.decide(approval, approve: true)
                    }
                    .compact().fixedSize()
                }
                .citadelFont("t12")
                .padding(.horizontal, skin.size.s10).padding(.vertical, skin.size.s8)
                .background(
                    skin.color(skin.palette.warning).opacity(skin.opacity.o10),
                    in: RoundedRectangle(cornerRadius: skin.size.s10))
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(skin.animation(AinkradAnimationToken(curve: "linear", duration: 0.5)).repeatForever()) {
                caret = false
            }
            withAnimation(
                skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 2)).repeatForever(autoreverses: false)
            ) {
                ping = true
            }
        }
    }
}

/// Now, idle: a breathing tile (☾ idle, ⏸ paused, ＋ not hired), the last run, what is next in its queue.
struct IdleNow: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @State private var breathe = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let last = model.agentRuns[agent.id]?.first { !$0.isLive }
        let queue = model.queue(of: agent.id).prefix(3)
        let violet = skin.color(skin.palette.accentViolet)
        BentoBox {
            Text("Now").citadelFont("t10_5", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
            HStack(spacing: skin.size.s14) {
                Text(agent.isHirePending ? "＋" : agent.isPaused ? "⏸" : "☾").citadelFont("t20").foregroundStyle(violet)
                    .frame(width: skin.size.s52, height: skin.size.s52)
                    .background(
                        RadialGradient(
                            colors: [violet.opacity(skin.opacity.o35), violet.opacity(skin.opacity.o08)],
                            center: UnitPoint(x: 0.3, y: 0.3), startRadius: 0, endRadius: skin.size.s52),
                        in: RoundedRectangle(cornerRadius: skin.size.s16)
                    )
                    .scaleEffect(breathe ? 1.05 : 1)
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text(
                        agent.isHirePending
                            ? "Not hired yet" : agent.isPaused ? "Paused by you" : "Idle — waiting for work"
                    )
                    .citadelFont("t15", weight: "semibold")
                    Group {
                        if agent.isHirePending {
                            Text("Approve the hire to seat it in its team.")
                        } else if let last {
                            Text(
                                "Last run #\(last.id) on \(model.issue(last.issueID)?.key ?? "—") · \(Fmt.age(Date().timeIntervalSince(last.endedAt ?? last.queuedAt))) ago"
                            )
                        } else {
                            Text("It wakes when an issue is assigned.")
                        }
                    }
                    .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                }
            }
            .padding(.vertical, skin.size.s4)
            if queue.isEmpty {
                Text("Nothing queued.").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
            } else {
                Text("Next in its queue").citadelFont("t10_5", weight: "semibold").foregroundStyle(
                    skin.color(skin.text.muted))
                ForEach(Array(queue)) { issue in
                    HStack(spacing: skin.size.s8) {
                        Text(issue.key).citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.palette.accentSecondary))
                        Text(issue.title).citadelFont("t12").lineLimit(1)
                        Spacer()
                        if let points = issue.points {
                            Text("\(points) pts").citadelFont("t11", mono: true).foregroundStyle(
                                skin.color(skin.text.faint))
                        }
                    }
                    .padding(.horizontal, skin.size.s10).frame(height: skin.size.s34)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o05)),
                        in: RoundedRectangle(cornerRadius: skin.size.s9))
                }
            }
            Spacer(minLength: 0)
            if !agent.isHirePending {
                HStack(spacing: skin.size.s8) {
                    AinkradButton(title: "Wake now") {}.disabled(true).fixedSize()
                        .help("Needs server: POST /agents/{id}/wake")
                    AinkradButton(title: "Assign an issue…", style: .secondary) {
                        store.screen = .projects
                        store.detail = nil
                    }
                    .fixedSize()
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 2)).repeatForever()) {
                breathe = true
            }
        }
    }
}

/// `Recent runs  n  All runs →` and a horizontal row of 230 pt run cards.
struct AgentRunCards: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let runs = (model.agentRuns[agent.id] ?? []).filter { !$0.isLive }
        if !runs.isEmpty {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                SectionHead(title: "Recent runs", count: "\(runs.count)", link: "All runs →") {
                    store.screen = .runs
                    store.detail = nil
                }
                ScrollView(.horizontal) {
                    HStack(spacing: skin.size.s10) {
                        ForEach(runs.prefix(8)) { run in RunCard(store: store, model: model, run: run) }
                    }
                    .padding(.vertical, skin.size.s4)
                }
                .scrollIndicators(.never)
            }
        }
    }
}

private struct RunCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        let tint = RunStatePill.tint(run, skin)
        let flagged = run.endWord != "succeeded" && run.endWord != "cancelled"
        AinkradTapArea {
            store.open(.run(run.id))
        } label: {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                HStack {
                    Text(model.issue(run.issueID)?.key ?? "#\(run.id)").citadelFont("t11", mono: true)
                        .foregroundStyle(skin.color(skin.palette.accentSecondary))
                    Spacer()
                    RunStatePill(run: run)
                }
                Text(model.issue(run.issueID)?.title ?? model.runTitle(run)).citadelFont("t12_5", weight: "medium")
                    .lineLimit(2).frame(height: skin.size.s34, alignment: .topLeading)
                HStack {
                    Text(Fmt.age(run.duration))
                    Spacer()
                    Text("\(Fmt.tokens(run.tokens)) tok")
                    Spacer()
                    Text(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "unpriced")
                }
                .citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
                GeometryReader { geo in
                    ZStack(alignment: .leading) {
                        Capsule().fill(skin.color(.palette("foreground", skin.opacity.o08)))
                        Capsule().fill(
                            flagged ? tint : skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o70)
                        )
                        .frame(
                            width: geo.size.width * min(1, Double(run.tokens) / Double(max(model.runCap ?? 200_000, 1)))
                        )
                    }
                }
                .frame(height: skin.size.s3)
            }
            .padding(skin.size.s12)
            .frame(width: skin.size.s232)
            .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o05))))
            .overlay(
                shape.strokeBorder(
                    flagged
                        ? tint.opacity(skin.opacity.o30)
                        : skin.color(.palette("foreground", hovering ? skin.opacity.o16 : skin.opacity.o08)),
                    lineWidth: 1)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .offset(y: hovering ? -skin.size.s3 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}
