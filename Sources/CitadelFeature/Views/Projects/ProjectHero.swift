import AinkradAppKit
import SwiftUI

/// The project page's hero (`.stage`, `project-board.js` `projPage`): the big mark, name and key, sprint status,
/// team / lead / repos / profile chips, who works on it now, three stats and the action dock — tinted by the
/// project's colours, its glows drifting and leaning against the cursor. Away from Overview it slims down.
struct ProjectHero: View {
    let store: CitadelStore
    let facts: ProjectFacts
    let slim: Bool
    @State private var lean: CGPoint = .zero
    @State private var drift = false
    @State private var size: CGSize = .zero
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: ProjectsPage { facts.page }
    private var tint: (Color, Color) { facts.tint }
    /// The cursor across the hero, −0.5…0.5 (0 when away): the glows lean against it, the mark toward it.
    private var mx: CGFloat { lean == .zero || size.width == 0 ? 0 : lean.x / size.width - 0.5 }
    private var my: CGFloat { lean == .zero || size.height == 0 ? 0 : lean.y / size.height - 0.5 }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s22, style: .continuous)
        HStack(alignment: .top, spacing: skin.size.s26) {
            left
            VStack(alignment: .leading, spacing: slim ? skin.size.s10 : skin.size.s16) {
                HStack(alignment: .top, spacing: skin.size.s26) {
                    identity
                        .frame(
                            maxWidth: .infinity, minHeight: slim ? skin.size.s64 : skin.size.s120, alignment: .leading)
                    if !slim { stats.frame(width: skin.size.s300).transition(.opacity) }
                }
                dock
            }
        }
        .padding(.top, slim ? skin.size.s12 : skin.size.s18)
        .padding(.bottom, slim ? skin.size.s12 : skin.size.s16)
        .padding(.horizontal, slim ? skin.size.s18 : skin.size.s22)
        .background { backdrop.mask(shape) }
        .onGeometryChange(for: CGSize.self) {
            $0.size
        } action: {
            size = $0
        }
        .overlay(shape.strokeBorder(tint.0.opacity(skin.opacity.o30), lineWidth: 1))
        .shadow(color: skin.color(.palette("black", skin.opacity.o35)), radius: skin.size.s26, y: skin.size.s18)
        .onContinuousHover { phase in
            guard !reduceMotion else { return }
            withAnimation(skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.8))) {
                switch phase {
                case .active(let at): lean = at
                case .ended: lean = .zero
                }
            }
        }
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 16)).repeatForever()) {
                drift = true
            }
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: slim)
    }

    // MARK: - Backdrop

    private var backdrop: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                LinearGradient(
                    stops: [
                        .init(color: tint.0.opacity(skin.opacity.o16), location: 0),
                        .init(color: skin.color(.palette("background", skin.opacity.o90)), location: 0.55),
                        .init(color: tint.1.opacity(skin.opacity.o14), location: 1),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing)
                glow(tint.0.opacity(skin.opacity.o55), side: skin.size.s520)
                    .offset(
                        x: -skin.size.s160 + mx * -36 + (drift ? 60 : 0),
                        y: -skin.size.s240 + my * -26 + (drift ? 24 : 0))
                glow(tint.1.opacity(skin.opacity.o45), side: skin.size.s440)
                    .offset(
                        x: skin.size.s40 + mx * 28 - (drift ? 48 : 0),
                        y: geo.size.height - skin.size.s180 + my * 22 - (drift ? 28 : 0))
                glow(tint.0.opacity(skin.opacity.o22), side: skin.size.s380)
                    .offset(x: geo.size.width * 0.96 - skin.size.s380 + mx * 18, y: -skin.size.s220)
            }
        }
        .allowsHitTesting(false)
    }

    private func glow(_ color: Color, side: CGFloat) -> some View {
        RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: side / 2)
            .frame(width: side, height: side)
    }

    // MARK: - Left

    private var left: some View {
        VStack(alignment: .leading, spacing: skin.size.s4) {
            if !slim {
                AinkradTapArea(help: "All projects", action: store.closeProject) {
                    Text("‹ Projects").citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                        .padding(.horizontal, skin.size.s6).padding(.vertical, skin.size.s2)
                }
            }
            ProjectMark(glyph: facts.glyph, tint: tint, side: slim ? skin.size.s64 : skin.size.s120)
                .offset(x: mx * skin.size.s10, y: my * skin.size.s8)
                .help("Logo upload needs the server (MISSING `PUT /projects/{id}/logo`)")
                .padding(.top, slim ? skin.size.s2 : skin.size.s6)
        }
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .firstTextBaseline, spacing: skin.size.s10) {
                Text(facts.project.name).citadelFont(slim ? "t21" : "t30", weight: "bold").tracking(-skin.size.s1 / 2)
                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                Text(facts.project.key).citadelFont("t11", weight: "bold").tracking(skin.size.s1)
                    .foregroundStyle(tint.0)
                    .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s3)
                    .background(tint.0.opacity(skin.opacity.o18), in: RoundedRectangle(cornerRadius: skin.size.s7))
            }
            status.padding(.top, skin.size.s8)
            if !slim {
                meta.padding(.top, skin.size.s10)
                if !facts.busy.isEmpty { live.padding(.top, skin.size.s12) }
            }
        }
    }

    private var status: some View {
        let busy = !facts.busy.isEmpty
        let cyan = skin.color(skin.palette.accentSecondary)
        return HStack(spacing: skin.size.s8) {
            Circle().fill(busy ? cyan : skin.color(skin.text.faint)).frame(width: skin.size.s8, height: skin.size.s8)
                .background(Circle().stroke(cyan.opacity(busy ? skin.opacity.o18 : 0), lineWidth: skin.size.s4))
            if facts.isScrum, let active = facts.active {
                Text("Sprint \(active.name)").citadelFont("t12_5", weight: "bold").foregroundStyle(
                    busy ? cyan : skin.color(skin.text.primary))
                Text(facts.sprintLine ?? "").citadelFont("t12_5").foregroundStyle(skin.color(skin.text.muted))
                    .lineLimit(1)
            } else {
                Text(facts.isScrum ? "No sprint" : "Kanban").citadelFont("t12_5", weight: "bold")
                    .foregroundStyle(busy ? cyan : skin.color(skin.text.primary))
                Text("\(facts.work.open.count) open issues").citadelFont("t12_5").foregroundStyle(
                    skin.color(skin.text.muted))
            }
        }
        .padding(.horizontal, skin.size.s12)
        .frame(height: skin.size.s30)
        .background(skin.color(.palette("black", skin.opacity.o25)), in: RoundedRectangle(cornerRadius: skin.size.s9))
    }

    private var meta: some View {
        AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
            ForEach(facts.teams) { team in
                MetaChip {
                    Text(team.name)
                } tap: {
                    page.drawer = .config(.teams)
                }
            }
            if let lead = facts.lead {
                MetaChip {
                    AgentFigure(agent: lead, model: facts.model, size: skin.size.s16)
                    Text("★ \(lead.name)")
                } tap: {
                    store.open(.agent(lead.id))
                }
            }
            MetaChip {
                Text("\(facts.repos.count) repo\(facts.repos.count == 1 ? "" : "s")")
            } tap: {
                page.drawer = .config(.repos)
            }
            if let profile = facts.profile, profile.budgetBytes > 0 {
                MetaChip {
                    Text("profile \(Fmt.tokens(profile.injectedBytes)) / \(Fmt.tokens(profile.budgetBytes)) bytes")
                } tap: {
                    page.drawer = .config(.context)
                }
                .help("Injected into every run on \(facts.project.key)")
            }
        }
    }

    private var live: some View {
        HStack(spacing: 0) {
            ForEach(facts.busy) { agent in
                LiftOnHover {
                    AinkradTapArea(help: agent.name, action: { store.open(.agent(agent.id)) }) {
                        AgentFigure(agent: agent, model: facts.model, size: skin.size.s30)
                    }
                }
                .padding(.trailing, -skin.size.s6)
            }
            Text("\(facts.busy.count) working now").citadelFont("t12").foregroundStyle(
                skin.color(skin.palette.accentSecondary)
            )
            .padding(.leading, skin.size.s16)
        }
    }

    // MARK: - Stats

    private var stats: some View {
        let work = facts.work
        let done = work.items.filter(\.isDone).count
        return VStack(alignment: .leading, spacing: skin.size.s8) {
            StatTile {
                AinkradRingGauge(
                    value: facts.progress, tint: skin.color(skin.palette.accentSecondary), diameter: skin.size.s64,
                    lineWidth: skin.size.s7
                ) {
                    Text("\(Int(facts.progress * 100))%").citadelFont("t12", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary))
                }
            } value: {
                if facts.isScrum, let report = facts.report {
                    Text("\(report.completed)")
                        + Text(" / \(report.committed) pts").font(small).foregroundStyle(skin.color(skin.text.muted))
                } else {
                    Text("\(done)") + Text(" done").font(small).foregroundStyle(skin.color(skin.text.muted))
                }
            } caption: {
                facts.isScrum && facts.report != nil ? "sprint progress" : "issues closed"
            }
            StatTile {
                FlowBar(flow: work.flow, thickness: skin.size.s14, vertical: true).frame(height: skin.size.s56)
                    .frame(width: skin.size.s64)
            } value: {
                Text("\(work.open.count)") + Text(" open").font(small).foregroundStyle(skin.color(skin.text.muted))
            } caption: {
                "\(facts.blocked) blocked · \(facts.inReview) in review"
            }
            StatTile {
                AinkradRingGauge(
                    value: nil, tint: skin.color(skin.palette.warning), diameter: skin.size.s64, lineWidth: skin.size.s7
                ) {
                    Text("$").citadelFont("t12", weight: "semibold", mono: true).foregroundStyle(
                        skin.color(skin.text.muted))
                }
            } value: {
                Text(work.monthSpend.map { Fmt.dollars(micros: $0) } ?? "—")
                    + Text(" this month").font(small).foregroundStyle(skin.color(skin.text.muted))
            } caption: {
                "across \(facts.agents.count) agents"
            }
        }
    }

    private var small: Font { skin.font(AinkradFontToken(sizeKey: "t11", weight: "medium")) }

    // MARK: - Dock

    private var dock: some View {
        let id = facts.project.id
        return HStack(spacing: skin.size.s6) {
            AinkradDockButton("New item", systemImage: "plus", tone: .primary) { store.newItem(project: id) }
            if facts.isScrum {
                if let next = facts.work.next {
                    AinkradDockButton("Plan \(next.name)", systemImage: "clock") { page.tab = .backlog }
                } else {
                    AinkradDockButton("Sprints", systemImage: "clock") { page.tab = .sprints }
                }
            }
            AinkradDockSeparator()
            AinkradDockButton("Repos", systemImage: ConfigTab.repos.icon) { page.drawer = .config(.repos) }
            AinkradDockButton("Rules", systemImage: ConfigTab.rules.icon) { page.drawer = .config(.rules) }
            AinkradDockButton("Runtime", systemImage: ConfigTab.runtime.icon) { page.drawer = .config(.runtime) }
            AinkradDockButton("Limits", systemImage: ConfigTab.limits.icon) { page.drawer = .config(.limits) }
            Spacer(minLength: skin.size.s6)
            AinkradDockButton("Run context", systemImage: "eye") { page.drawer = .config(.context) }
        }
    }
}

/// A hero chip (`.st-meta .chip`): h26, r8, white .07 over a hairline.
private struct MetaChip<Label: View>: View {
    @ViewBuilder let label: Label
    let tap: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(action: tap) {
            HStack(spacing: skin.size.s6) { label }
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.primary))
                .padding(.horizontal, skin.size.s10)
                .frame(height: skin.size.s26)
                .background(
                    skin.color(.palette("foreground", hovering ? skin.opacity.o12 : skin.opacity.o07)),
                    in: RoundedRectangle(cornerRadius: skin.size.s8)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: skin.size.s8).strokeBorder(
                        skin.color(.palette("foreground", skin.opacity.o08))))
        }
        .onHover { hovering = $0 }
    }
}

/// A hero stat (`.sst`): visual, bold value, faint caption; nudges left on hover.
private struct StatTile<Visual: View>: View {
    @ViewBuilder let visual: Visual
    let value: () -> Text
    let caption: () -> String
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        HStack(spacing: skin.size.s12) {
            visual
            VStack(alignment: .leading, spacing: skin.size.s1) {
                value().citadelFont("t17", weight: "bold").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                Text(caption()).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, skin.size.s8).padding(.leading, skin.size.s8).padding(.trailing, skin.size.s14)
        .frame(minWidth: skin.size.s220)
        .background(shape.fill(skin.color(.palette("black", hovering ? skin.opacity.o30 : skin.opacity.o22))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o06))))
        .offset(x: hovering && !reduceMotion ? -skin.size.s2 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// Lifts its content 2 pt while hovered.
struct LiftOnHover<Content: View>: View {
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        content
            .offset(y: hovering && !reduceMotion ? -skin.size.s2 : 0)
            .onHover { hovering = $0 }
            .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}
