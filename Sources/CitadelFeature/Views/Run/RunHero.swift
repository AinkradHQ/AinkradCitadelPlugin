import AinkradAppKit
import SwiftUI

/// The run's hero (`.rq-hero.run-hero`): the agent in its well, `‹ Runs › #418`, key and title, the state and meta
/// chips, the token ring and numbers, and the dock — Follow live and Stop only while it runs.
struct RunHero: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    let followsLive: Bool
    let toggleFollow: () -> Void
    let stop: () -> Void
    @Environment(\.ainkradSkin) private var skin

    private var agent: AgentInfo? { model.agent(run.agentID) }
    private var look: RunLook { model.look(run) }
    private var colors: (Color, Color) {
        agent?.washColors(skin) ?? (skin.color(skin.palette.accentSecondary), skin.color(skin.palette.accentPrimary))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(alignment: .center, spacing: skin.size.s16) {
                if let agent {
                    AgentFigure(agent: agent, model: model, size: skin.size.s56, isActive: look.isLive)
                        .frame(width: skin.size.s64, height: skin.size.s64)
                        .background(
                            skin.color(.palette("black", skin.opacity.o18)),
                            in: RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
                        )
                        .overlay(
                            RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
                                .strokeBorder(skin.color(.palette("foreground", skin.opacity.o06)), lineWidth: 1))
                }
                identity.frame(maxWidth: .infinity, alignment: .leading)
                stats
            }
            dock
        }
        .padding(.horizontal, skin.size.s18)
        .padding(.vertical, skin.size.s16)
        .runWash(colors, radius: skin.size.s20, strength: 0.85)
        .padding(.horizontal, skin.size.s14)
        .padding(.top, skin.size.s14)
        .padding(.bottom, skin.size.s6)
    }

    private var identity: some View {
        let issue = model.issue(run.issueID)
        return VStack(alignment: .leading, spacing: skin.size.s3) {
            HStack(spacing: skin.size.s6) {
                CrumbLink(text: "‹ Runs") { store.go(.runs) }
                Text("›")
                Text("#\(run.id)").citadelFont("t11", mono: true)
            }
            .citadelFont("t11")
            .foregroundStyle(skin.color(skin.text.faint))
            HStack(alignment: .firstTextBaseline, spacing: skin.size.s8) {
                if let issue {
                    Text(issue.key).citadelFont("t13", weight: "medium", mono: true)
                        .foregroundStyle(skin.color(skin.palette.accentSecondary))
                }
                Text(issue?.title ?? model.runTitle(run)).citadelFont("t18", weight: "bold")
                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
            }
            AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                stateChip
                if let agent {
                    RunMetaChip(action: { store.open(.agent(agent.id)) }) {
                        AgentFigure(agent: agent, model: model, size: skin.size.s16)
                        Text("\(agent.name) · \(agent.role)")
                    }
                }
                RunMetaChip {
                    Text(AgentLook.harnessName(run.harness))
                    if let name = run.model ?? agent?.model { Text("· \(name)").citadelFont("t11", mono: true) }
                }
                if let account = run.accountID.flatMap({ model.accounts[$0] }) {
                    RunMetaChip(action: { store.go(.accounts) }) {
                        Image(systemName: "key").citadelFont("t10")
                        Text(account.label).citadelFont("t11", mono: true)
                    }
                }
                if let runner = run.runnerID.flatMap({ model.runners[$0] }) {
                    RunMetaChip(action: { store.go(.runners) }) {
                        Image(systemName: "server.rack").citadelFont("t10")
                        Text(runner).citadelFont("t11", mono: true)
                    }
                }
            }
            .padding(.top, skin.size.s5)
        }
    }

    /// `● running · 4m 53s` (ticking) or `● runner lost · 31m`.
    private var stateChip: some View {
        let tint = Hue(look.tone).color(skin)
        return TimelineView(.periodic(from: .now, by: 1)) { context in
            let elapsed = model.elapsed(run, now: context.date)
            OutcomeChip(
                text: "\(look.word) · \(look.isLive ? Fmt.duration(elapsed) : RunLook.span(elapsed))", tint: tint)
        }
    }

    private var stats: some View {
        let cap = model.cap(of: run)
        let cost = model.cost(run)
        return HStack(spacing: skin.size.s12) {
            if let cap, cap > 0 {
                let fraction = Double(run.tokens) / Double(cap)
                AinkradRingGauge(
                    value: fraction, tint: ringTint(fraction), diameter: skin.size.s56, lineWidth: skin.size.s7
                ) {
                    Text("\(Int(min(fraction, 1) * 100))%").citadelFont("t12", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary))
                }
            }
            Grid(alignment: .leading, horizontalSpacing: skin.size.s8, verticalSpacing: skin.size.s1) {
                GridRow {
                    Text("\(Fmt.tokens(run.tokens))\(cap.map { " / \(Fmt.tokens($0))" } ?? "")")
                        .citadelFont("t13", weight: "semibold", mono: true).foregroundStyle(
                            skin.color(skin.text.primary)
                        )
                        .gridColumnAlignment(.trailing)
                    Text("tokens").citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                }
                GridRow {
                    Text(cost.word).citadelFont("t13", weight: "semibold", mono: true)
                        .foregroundStyle(
                            cost == .unpriced ? skin.color(skin.palette.warning) : skin.color(skin.palette.success))
                    Text("cost").citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                }
            }
        }
    }

    private func ringTint(_ fraction: Double) -> Color {
        fraction >= 1
            ? skin.color(skin.palette.danger)
            : fraction >= model.warnFraction ? skin.color(skin.palette.warning) : colors.0
    }

    private var dock: some View {
        let issue = model.issue(run.issueID)
        return HStack(spacing: skin.size.s6) {
            if look.isLive {
                DockToggle(
                    "Follow live", systemImage: "arrow.down", isOn: followsLive, help: "⌘↓", action: toggleFollow)
                AinkradDockButton("Stop", systemImage: "stop", tone: .danger, action: stop)
                AinkradDockSeparator()
            }
            if let issue {
                AinkradDockButton("Open \(issue.key)", systemImage: "text.alignleft") {
                    if let requirement = issue.requirementID {
                        store.goRequirement(requirement)
                    } else {
                        store.open(.agent(run.agentID))
                    }
                }
            }
            if let agent {
                DockToggle(title: agent.name, action: { store.open(.agent(agent.id)) }) {
                    AgentFigure(agent: agent, model: model, size: skin.size.s16)
                }
            }
            // TODO(citadel#forge-open): hand the worktrees to Forge once the host has a cross-plugin open intent.
            DockToggle(
                "Worktree in Forge", systemImage: "arrow.triangle.branch", isEnabled: false,
                help: "Needs the host's cross-plugin open (not yet available)", action: {})
            AinkradDockButton("Transcript", systemImage: "arrow.down.to.line") { store.downloadTranscript(run) }
            AinkradDockButton("Copy link", systemImage: "doc.on.doc") { store.copyRunLink(run) }
        }
    }
}

/// A faint crumb that brightens on hover and goes back.
struct CrumbLink: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(action: action) {
            Text(text).foregroundStyle(skin.color(hovering ? skin.text.primary : skin.text.faint))
        }
        .onHover { hovering = $0 }
    }
}
