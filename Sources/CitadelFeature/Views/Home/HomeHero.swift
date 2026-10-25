import AinkradAppKit
import SwiftUI

/// Home's hero (prototype `home.js` hero): the company core with its agents in orbit (busy ones on the inner
/// dashed ring), the greeting, company name and live status line, the dock, and four ring stats.
struct HomeHero: View {
    let store: CitadelStore
    let model: CompanyModel
    let confirmPause: () -> Void
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var drift = false
    @State private var width: CGFloat = 0

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s24, style: .continuous)
        // The prototype's 1350 px breakpoint, as the pane sees it: stats move under the identity below it.
        Group {
            if width == 0 || width >= skin.size.s860 + skin.size.s140 {
                HStack(alignment: .center, spacing: skin.size.s24) {
                    orbit
                    identity.frame(maxWidth: .infinity, alignment: .leading)
                    stats.frame(width: skin.size.s440 + skin.size.s20)
                }
            } else {
                VStack(alignment: .leading, spacing: skin.size.s16) {
                    HStack(alignment: .center, spacing: skin.size.s20) {
                        orbit
                        identity.frame(maxWidth: .infinity, alignment: .leading)
                    }
                    stats
                }
            }
        }
        .onGeometryChange(for: CGFloat.self) {
            $0.size.width
        } action: {
            width = $0
        }
        .padding(.vertical, skin.size.s18)
        .padding(.leading, skin.size.s14)
        .padding(.trailing, skin.size.s24)
        .frame(minHeight: skin.size.s220 + skin.size.s10)
        .background {
            ZStack {
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o20), location: 0),
                            .init(color: skin.color(.palette("background", skin.opacity.o88)), location: 0.45),
                            .init(color: skin.color(skin.palette.accentViolet).opacity(skin.opacity.o16), location: 1),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
                glow(skin.color(skin.palette.accentPrimary), size: skin.size.s420, at: .topLeading)
                glow(skin.color(skin.palette.accentViolet), size: skin.size.s360, at: .bottomTrailing)
            }
            .compositingGroup()
            .mask(shape)
        }
        .overlay(shape.strokeBorder(skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o22), lineWidth: 1))
        .shadow(color: skin.color(.palette("black", skin.opacity.o30)), radius: skin.size.s30, y: skin.size.s20)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 9)).repeatForever()) {
                drift = true
            }
        }
    }

    private func glow(_ color: Color, size: CGFloat, at corner: Alignment) -> some View {
        let sign: CGFloat = corner == .topLeading ? 1 : -1
        return RadialGradient(
            colors: [color.opacity(skin.opacity.o35), .clear], center: .center, startRadius: 0, endRadius: size / 2
        )
        .frame(width: size, height: size)
        .scaleEffect(drift ? 1.15 : 1)
        .offset(
            x: sign * (drift ? skin.size.s40 : 0) - sign * size / 3,
            y: sign * (drift ? skin.size.s20 : 0) - sign * size / 3
        )
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: corner)
        .allowsHitTesting(false)
    }

    // MARK: - Orbit

    private var orbit: some View {
        HomeOrbit(store: store, model: model).frame(
            width: skin.size.s200 + skin.size.s10, height: skin.size.s200 + skin.size.s10)
    }

    // MARK: - Identity

    private var identity: some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            Text(greeting).citadelFont("t13").foregroundStyle(
                skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o90))
            Text(store.company?.name ?? CitadelApp.displayName).citadelFont("t34", weight: "heavy").tracking(
                -skin.size.s1 / 2
            )
            .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
            statusLine
            dock.padding(.top, skin.size.s10)
        }
    }

    private var greeting: String {
        let hour = Calendar.current.component(.hour, from: Date())
        let part = hour < 12 ? "morning" : hour < 18 ? "afternoon" : "evening"
        return store.userName.map { "Good \(part), \($0)" } ?? "Good \(part)"
    }

    private var statusLine: some View {
        let live = store.streamStatus == .live
        return AinkradFlowLayout(spacing: skin.size.s8, lineSpacing: skin.size.s4) {
            HStack(spacing: skin.size.s6) {
                Circle().fill(live ? status.success : status.warning).frame(width: skin.size.s6, height: skin.size.s6)
                    .breathing(live)
                Text(live ? "live" : "polling").citadelFont("t11", weight: "semibold")
            }
            .foregroundStyle(live ? status.success : status.warning)
            .padding(.horizontal, skin.size.s9)
            .frame(height: skin.size.s22)
            .background(
                (live ? status.success : status.warning).opacity(skin.opacity.o12),
                in: RoundedRectangle(cornerRadius: skin.size.s7))
            (Text("\(model.liveRuns.count)").bold().foregroundStyle(skin.color(skin.text.primary))
                + Text(" runs working"))
            Text("·").foregroundStyle(skin.color(skin.text.faint))
            (Text("\(model.needsYouCount)").bold() + Text(" need you"))
                .foregroundStyle(model.needsYouCount > 0 ? status.warning : status.success)
            if let sprint = model.sprint {
                Text("·").foregroundStyle(skin.color(skin.text.faint))
                Text("sprint ")
                    + Text(Wording.sprintName(sprint.title)).font(
                        skin.font(AinkradFontToken(sizeKey: "t13", mono: "family")))
                    + Text(sprintDay(sprint))
            }
        }
        .citadelFont("t13")
        .foregroundStyle(skin.color(skin.text.muted))
    }

    private func sprintDay(_ sprint: SprintInfo) -> String {
        guard let start = sprint.startsOn, let end = sprint.endsOn else { return "" }
        let day = (Calendar.current.dateComponents([.day], from: start, to: Date()).day ?? 0) + 1
        let length = (Calendar.current.dateComponents([.day], from: start, to: end).day ?? 0) + 1
        return " day \(min(day, length)) of \(length)"
    }

    private var allPaused: Bool {
        let hired = model.agents.values.filter { !$0.isHirePending && $0.status != "terminated" }
        return !hired.isEmpty && hired.allSatisfy(\.isPaused)
    }

    private var dock: some View {
        AinkradFlowLayout(spacing: skin.size.s6) {
            AinkradDockButton("New requirement", systemImage: "plus", tone: .primary) {
                store.isComposingRequirement = true
            }
            .help("New requirement · ⌘N")
            if allPaused {
                AinkradDockButton("Resume all", systemImage: "play", tone: .success) { store.setCompanyPaused(false) }
            } else {
                AinkradDockButton("Pause all runs", systemImage: "pause", isEnabled: !model.agents.isEmpty) {
                    confirmPause()
                }
            }
            AinkradDockButton("Org", systemImage: Screen.org.icon) { store.screen = .org }
            AinkradDockButton("Settings", systemImage: "gearshape") { store.isShowingSettings = true }
        }
    }

    // MARK: - Stats

    private var stats: some View {
        let today = model.spendToday?.costMicros ?? 0
        let sprint = model.sprint
        let working = model.busyAgents
        return Grid(horizontalSpacing: skin.size.s10, verticalSpacing: skin.size.s10) {
            GridRow {
                StatRing(
                    value: model.needsYouCount > 0 ? 1 : 0,
                    tint: model.needsYouCount > 0 ? status.warning : status.success,
                    label: "\(model.needsYouCount)", title: model.needsYouCount > 0 ? "Needs you" : "All clear",
                    caption: "\(model.approvals.count) approve · \(model.stuck.count) stuck"
                ) { store.screen = .approvals }
                StatRing(
                    value: model.agents.isEmpty ? 0 : Double(working) / Double(model.agents.count),
                    tint: skin.color(skin.palette.accentSecondary), label: "\(working)", title: "Working now",
                    caption: "\(model.liveRuns.count) runs · \(model.idleAgents) idle"
                ) { store.screen = .runs }
            }
            GridRow {
                StatRing(
                    value: nil, tint: skin.color(skin.palette.accentPrimary), label: "$",
                    title: Fmt.dollars(micros: today),
                    caption: "spent today · \(Fmt.tokens(model.spendToday?.tokens ?? 0)) tok"
                ) { store.screen = .cost }
                StatRing(
                    value: sprint.map { Double($0.completed) / Double(max($0.committed, 1)) },
                    tint: status.success,
                    label: sprint.map { "\(Int(Double($0.completed) / Double(max($0.committed, 1)) * 100))%" } ?? "—",
                    title: sprint.map { "\($0.completed)/\($0.committed) pts" } ?? "No sprint",
                    caption: sprint.map { "sprint \(Wording.sprintName($0.title))" } ?? "plan one in Projects"
                ) { store.screen = .projects }
            }
        }
    }
}

/// One hero stat: a 64 pt ring with its label, a bold value and a faint caption; lifts on hover.
private struct StatRing: View {
    let value: Double?
    let tint: Color
    let label: String
    let title: String
    let caption: String
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        AinkradTapArea(action: open) {
            HStack(spacing: skin.size.s12) {
                AinkradRingGauge(value: value, tint: tint, diameter: skin.size.s64, lineWidth: skin.size.s7) {
                    Text(label).citadelFont("t13", weight: "bold", mono: true).foregroundStyle(
                        skin.color(skin.text.primary))
                }
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text(title).citadelFont("t15", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                        .lineLimit(1)
                    Text(caption).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.vertical, skin.size.s12)
            .padding(.leading, skin.size.s12)
            .padding(.trailing, skin.size.s16)
            .background(shape.fill(skin.color(.palette("background", skin.opacity.o45))))
            .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o22), lineWidth: 1))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .offset(y: hovering && !reduceMotion ? -skin.size.s3 : 0)
        .animation(skin.animation(AinkradAnimationToken(curve: "spring", response: 0.3, damping: 0.7)), value: hovering)
        .onHover { hovering = $0 }
    }
}

/// The agent constellation: outer ring of resting agents (slow, reverse), inner dashed ring of busy ones, the
/// company core pinging in the middle. Hovering pauses the orbit; a figure opens its agent.
private struct HomeOrbit: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var paused = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let agents = model.agents.values.filter { !$0.isHirePending && $0.status != "terminated" }.sorted {
            $0.id < $1.id
        }
        let busy = agents.filter { [.working, .thinking, .loading].contains($0.figure) }
        let rest = Array(agents.filter { ![.working, .thinking, .loading].contains($0.figure) }.prefix(12))
        GeometryReader { geo in
            let side = min(geo.size.width, geo.size.height)
            let outer = side / 2
            let inner = outer * 0.6
            TimelineView(.animation(minimumInterval: 1.0 / 30, paused: paused || reduceMotion)) { context in
                let t = context.date.timeIntervalSinceReferenceDate
                ZStack {
                    Circle().stroke(skin.color(.palette("foreground", skin.opacity.o06)), lineWidth: 1)
                        .frame(width: outer * 2, height: outer * 2)
                    Circle()
                        .stroke(
                            skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o30),
                            style: StrokeStyle(lineWidth: 1, dash: [skin.size.s3, skin.size.s4])
                        )
                        .frame(width: inner * 2, height: inner * 2)
                    core(side: skin.size.s64)
                    ForEach(Array(rest.enumerated()), id: \.element.id) { index, agent in
                        let angle = -t / 60 * 2 * .pi + Double(index) / Double(max(rest.count, 1)) * 2 * .pi
                        figure(agent, size: skin.size.s26)
                            .opacity(skin.opacity.o70)
                            .offset(x: cos(angle) * outer, y: sin(angle) * outer)
                    }
                    ForEach(Array(busy.enumerated()), id: \.element.id) { index, agent in
                        let angle = t / 28 * 2 * .pi + Double(index) / Double(max(busy.count, 1)) * 2 * .pi
                        figure(agent, size: skin.size.s36)
                            .shadow(
                                color: skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o60),
                                radius: skin.size.s8
                            )
                            .offset(x: cos(angle) * inner, y: sin(angle) * inner)
                    }
                }
                .frame(width: side, height: side)
            }
        }
        .onHover { paused = $0 }
    }

    private func figure(_ agent: AgentInfo, size: CGFloat) -> some View {
        AinkradTapArea {
            store.open(.agent(agent.id))
        } label: {
            AgentFigure(agent: agent, model: model, size: size, isActive: size > skin.size.s30)
        }
        .buttonStyle(.plain)
        .help("\(agent.name) · \(agent.role)")
    }

    private func core(side: CGFloat) -> some View {
        ZStack {
            PingRing(delay: 0, side: side)
            PingRing(delay: 1.5, side: side)
            if let company = store.company {
                CompanyMark(company: company, size: side, live: false, radius: skin.size.s20, fontKey: "t26")
            }
        }
    }
}

/// A ring that grows from the core and fades, every 3 s.
private struct PingRing: View {
    let delay: Double
    let side: CGFloat
    @State private var on = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        RoundedRectangle(cornerRadius: skin.size.s26, style: .continuous)
            .stroke(skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o60), lineWidth: 2)
            .frame(width: side + skin.size.s20, height: side + skin.size.s20)
            .scaleEffect(on ? 1.6 : 0.85)
            .opacity(on ? 0 : 1)
            .opacity(reduceMotion ? 0 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 3)).repeatForever(
                        autoreverses: false
                    )
                    .delay(delay)
                ) { on = true }
            }
    }
}
