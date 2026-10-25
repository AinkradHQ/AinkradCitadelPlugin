import AinkradAppKit
import SwiftUI

/// The agent page's hero (prototype `agent.js` `.stage`): a gradient tinted by the agent's palette with three
/// drifting glow layers that lean against the cursor, the 148 pt figure leaning toward it, identity, three ring
/// stats and the dock.
struct AgentStage: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @State private var cursor: CGPoint = .zero
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let palette = agent.palette
        let shape = RoundedRectangle(cornerRadius: skin.size.s22, style: .continuous)
        HStack(alignment: .top, spacing: skin.size.s26) {
            VStack(alignment: .leading, spacing: skin.size.s4) {
                AinkradTapArea {
                    store.open(nil)
                } label: {
                    Text("‹ Org").citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                }
                .buttonStyle(.plain)
                AgentFigure(agent: agent, model: model, size: skin.size.s150 - skin.size.s2, isActive: true)
                    .shadow(
                        color: palette.lightColor.opacity(skin.opacity.o45), radius: skin.size.s14, y: skin.size.s14
                    )
                    .offset(x: cursor.x * skin.size.s10, y: cursor.y * skin.size.s8)
                    .animation(
                        reduceMotion ? nil : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.4)),
                        value: cursor)
            }
            VStack(alignment: .leading, spacing: skin.size.s16) {
                HStack(alignment: .top, spacing: skin.size.s26) {
                    AgentIdentity(store: store, model: model, agent: agent).frame(
                        maxWidth: .infinity, alignment: .leading)
                    AgentStageStats(store: store, model: model, agent: agent)
                }
                AgentDock(store: store, model: model, agent: agent)
            }
        }
        .padding(.top, skin.size.s18)
        .padding(.horizontal, skin.size.s22)
        .padding(.bottom, skin.size.s16)
        .background {
            ZStack {
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: palette.lightColor.opacity(skin.opacity.o16), location: 0),
                            .init(color: skin.color(.palette("background", skin.opacity.o90)), location: 0.55),
                            .init(color: palette.deepColor.opacity(skin.opacity.o14), location: 1),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                AinkradParallaxGlow(light: palette.lightColor, deep: palette.deepColor, cursor: cursor)
            }
            .compositingGroup()
            .clipShape(shape)
        }
        .overlay(shape.strokeBorder(palette.lightColor.opacity(skin.opacity.o30), lineWidth: 1))
        .shadow(color: skin.color(.palette("black", skin.opacity.o35)), radius: skin.size.s24, y: skin.size.s18)
        .onContinuousHover(coordinateSpace: .local) { phase in
            guard !reduceMotion else { return }
            if case .active(let point) = phase, stageSize.width > 0 {
                cursor = CGPoint(x: point.x / stageSize.width - 0.5, y: point.y / stageSize.height - 0.5)
            } else {
                cursor = .zero
            }
        }
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            stageSize = $0
        }
    }

    @State private var stageSize: CGSize = .zero
}

private struct AgentIdentity: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let bucket = OrgBucket(agent)
        let live = model.currentRun(of: agent.id).flatMap { $0.isLive ? $0 : nil }
        let now =
            live.map { run in
                model.issue(run.issueID).map { "\($0.key) · \($0.title)" } ?? "run #\(run.id)"
            }
            ?? (agent.isHirePending
                ? "awaiting your approval" : model.orgLine(agent).text.components(separatedBy: " · ").last ?? "")
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: skin.size.s10) {
                Text(agent.name).citadelFont("t30", weight: "bold").tracking(-0.6)
                    .foregroundStyle(skin.color(skin.text.primary))
                Text(agent.role).citadelFont("t11", weight: "bold").tracking(0.9)
                    .foregroundStyle(agent.palette.lightColor)
                    .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s3)
                    .background(
                        agent.palette.lightColor.opacity(skin.opacity.o18),
                        in: RoundedRectangle(cornerRadius: skin.size.s7))
            }
            HStack(spacing: skin.size.s8) {
                Circle().fill(bucket.tint(skin)).frame(width: skin.size.s8, height: skin.size.s8)
                    .background(
                        Circle().fill(
                            skin.color(skin.palette.accentSecondary).opacity(bucket == .busy ? skin.opacity.o18 : 0)
                        )
                        .frame(width: skin.size.s16, height: skin.size.s16))
                Text(bucket.label).fontWeight(.semibold).foregroundStyle(
                    bucket == .idle ? skin.color(skin.text.primary) : bucket.tint(skin))
                Text(now).foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
            }
            .citadelFont("t12_5")
            .padding(.horizontal, skin.size.s12).frame(height: skin.size.s30)
            .background(
                skin.color(.palette("black", skin.opacity.o25)), in: RoundedRectangle(cornerRadius: skin.size.s9)
            )
            .padding(.top, skin.size.s8)
            AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                chip { Text(model.title(of: agent)) }
                if let boss = model.agent(agent.reportsTo) {
                    AinkradTapArea {
                        store.open(.agent(boss.id))
                    } label: {
                        chip {
                            AgentFigure(agent: boss, model: model, size: skin.size.s16)
                            Text("reports to \(boss.name)")
                        }
                    }
                    .buttonStyle(.plain)
                    .agentHoverCard(store, model, boss)
                } else {
                    chip { Text("reports to you") }
                }
                chip {
                    HarnessTag(harness: agent.harness, size: skin.size.s20)
                    Text(agent.model)
                }
                if let effort = agent.effort { chip { Text("\(effort) effort") } }
                if let sandbox = agent.sandbox { chip { Text(sandbox) } }
            }
            .padding(.top, skin.size.s10)
            if let about = agent.about, !about.isEmpty {
                Text(about).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted)).lineLimit(3)
                    .padding(.top, skin.size.s8)
            }
        }
    }

    private func chip<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: skin.size.s6) { content() }
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.primary))
            .padding(.horizontal, skin.size.s10).frame(height: skin.size.s26)
            .background(
                skin.color(.palette("foreground", skin.opacity.o07)), in: RoundedRectangle(cornerRadius: skin.size.s8)
            )
            .overlay(
                RoundedRectangle(cornerRadius: skin.size.s8).strokeBorder(
                    skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
    }
}

/// The three stat cards (`.sst`): month budget ring, this week's runs, success ring with the average cost.
private struct AgentStageStats: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let budget = model.monthBudget(of: agent.id)
        let stats = AgentStats(runs: model.agentRuns[agent.id] ?? [])
        let page = model.orgPage
        VStack(spacing: skin.size.s8) {
            StageStat(open: { page.drawer = .init(section: .settings, anchor: "budget") }) {
                ring(
                    budget?.fraction, warn: (budget?.fraction ?? 0) >= (budget?.warnFraction ?? 0.8),
                    label: budget.map { "\(Int(($0.fraction * 100).rounded()))%" } ?? "—")
            } text: {
                value(
                    budget?.spentWord ?? "No budget", small: budget.map { " / \($0.capWord)" }
                )
                caption("budget · \(Date().formatted(.dateTime.month(.abbreviated)))")
            }
            StageStat(open: {
                store.screen = .runs
                store.detail = nil
            }) {
                WeekBars(counts: stats.week, barWidth: skin.size.s6, height: skin.size.s52, unit: skin.size.s6)
                    .frame(width: skin.size.s64)
            } text: {
                value("\(stats.weekTotal)", small: " runs")
                caption("this week")
            }
            StageStat(open: {
                store.screen = .runs
                store.detail = nil
            }) {
                ring(
                    stats.successPercent.map { Double($0) / 100 }, warn: (stats.successPercent ?? 100) < 80,
                    good: true, label: stats.successPercent.map { "\($0)%" } ?? "—")
            } text: {
                value(stats.averageMicros.map { Fmt.dollars(micros: $0) } ?? "—", small: nil)
                caption("avg / run · \(stats.succeeded)/\(stats.finished) ok")
            }
        }
        .frame(minWidth: skin.size.s220)
        .fixedSize()
    }

    private func ring(_ value: Double?, warn: Bool, good: Bool = false, label: String) -> some View {
        AinkradRingGauge(
            value: value,
            tint: warn
                ? skin.color(skin.palette.warning)
                : good ? skin.color(skin.palette.success) : skin.color(skin.palette.accentSecondary),
            diameter: skin.size.s64, lineWidth: skin.size.s7
        ) {
            Text(label).citadelFont("t12", weight: "semibold", mono: true).foregroundStyle(
                skin.color(skin.text.primary))
        }
    }

    private func value(_ big: String, small: String?) -> some View {
        (Text(big).font(skin.font(AinkradFontToken(sizeKey: "t17", weight: "semibold")))
            + Text(small ?? "").font(skin.font(AinkradFontToken(sizeKey: "t11", weight: "medium")))
            .foregroundStyle(skin.color(skin.text.muted)))
            .foregroundStyle(skin.color(skin.text.primary))
    }

    private func caption(_ text: String) -> some View {
        Text(text).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
    }
}

private struct StageStat<Visual: View, Words: View>: View {
    let open: () -> Void
    @ViewBuilder let visual: Visual
    @ViewBuilder let text: Words
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        AinkradTapArea(action: open) {
            HStack(spacing: skin.size.s12) {
                visual
                VStack(alignment: .leading, spacing: skin.size.s2) { text }
                Spacer(minLength: 0)
            }
            .padding(.vertical, skin.size.s8).padding(.leading, skin.size.s8).padding(.trailing, skin.size.s14)
            .background(shape.fill(skin.color(.palette("black", hovering ? skin.opacity.o30 : skin.opacity.o22))))
            .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o06)), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .offset(x: hovering ? -skin.size.s2 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// The dock (`.st-dock`): Chat, the state's actions, the drawer's sections, and the hard stops on the right.
/// Labels always stay; the buttons wrap onto a second line when the stage is too narrow for one.
private struct AgentDock: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let page = model.orgPage
        let live = model.currentRun(of: agent.id).flatMap { $0.isLive ? $0 : nil }
        HStack(spacing: skin.size.s6) {
            AinkradFlowLayout(spacing: skin.size.s6) {
                AinkradDockButton("Chat", systemImage: "bubble.left") { store.chat(with: agent.id) }
                if agent.isHirePending, let approval = model.hireApproval(of: agent.id) {
                    AinkradDockButton("Approve hire", systemImage: "play", tone: .primary) {
                        store.decideHire(approval, approve: true)
                    }
                    AinkradDockButton("Reject", systemImage: "xmark.circle", tone: .danger) {
                        store.decideHire(approval, approve: false)
                    }
                } else if !agent.isHirePending {
                    if agent.isPaused {
                        AinkradDockButton("Resume", systemImage: "play", tone: .success) { store.resume(agent) }
                    } else {
                        AinkradDockButton("Pause", systemImage: "pause", tone: .warning) {
                            page.sheet = .pause(agent.id)
                        }
                    }
                    if let live {
                        AinkradDockButton("Open run", systemImage: "arrow.up.right.square", tone: .primary) {
                            store.open(.run(live.id))
                        }
                    } else {
                        AinkradDockButton(
                            "Wake now", systemImage: "bolt", tone: .primary,
                            isEnabled: store.serverSupports(minor: CitadelStore.structureMinor)
                        ) { store.wake(agent) }
                        .help(store.help(ready: "Run it on what is waiting for it"))
                    }
                }
                AinkradDockSeparator()
                AinkradDockButton("Instructions", systemImage: "doc.text") {
                    page.drawer = .init(section: .instructions)
                }
                AinkradDockButton("Budget", systemImage: "dollarsign.circle") {
                    page.drawer = .init(section: .settings, anchor: "budget")
                }
                AinkradDockButton("Model", systemImage: "cpu") {
                    page.drawer = .init(section: .settings, anchor: "model")
                }
                AinkradDockButton("Look", systemImage: "paintpalette") {
                    page.drawer = .init(section: .settings, anchor: "look")
                }
            }
            Spacer(minLength: 0)
            HStack(spacing: skin.size.s6) {
                if let live {
                    AinkradDockButton("Stop run", systemImage: "stop", tone: .danger) { page.sheet = .stopRun(live.id) }
                }
                if !agent.isHirePending {
                    AinkradDockButton("Terminate", systemImage: "xmark.circle", tone: .danger) {
                        page.sheet = .terminate(agent.id)
                    }
                }
            }
        }
    }
}
