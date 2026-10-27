import AinkradAppKit
import SwiftUI

/// Screen 14 (prototype `#/projects`): one rich card per project in its own colours — sprint ring and burndown (or
/// the Kanban flow bar), who works on it now, its repos and health — and a dashed card that starts a new one. A card
/// opens the project page (`#/projects/<KEY>`).
struct ProjectsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var creating = false
    @Environment(\.ainkradSkin) private var skin

    private var page: ProjectsPage { model.projectsPage }

    var body: some View {
        Group {
            if let id = page.openProject {
                if let project = model.projects.first(where: { $0.id == id }) {
                    ProjectPage(store: store, model: model, project: project) { creating = true }
                } else {
                    notFound
                }
            } else {
                list
            }
        }
        .task { if !page.isLoaded { store.loadProjectsPage() } }
        // ⌘K's New project… lands here.
        .task(id: store.pendingSheet) {
            guard store.pendingSheet == .newProject else { return }
            store.pendingSheet = nil
            creating = true
        }
        .ainkradSheet(isPresented: $creating) { NewProjectSheet(store: store, isPresented: $creating) }
    }

    private var list: some View {
        let working = model.agents.values.filter { [.working, .thinking].contains($0.figure) }.count
        let crumb = Text(
            "\(model.projects.count) project\(model.projects.count == 1 ? "" : "s")  ·  \(working) agents working"
        )
        .foregroundStyle(skin.color(skin.text.muted))
        return VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Projects", crumb: crumb) {
                AinkradButton(title: "＋ New project", style: .primary) { creating = true }.compact().fixedSize()
            }
            ScrollView {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: skin.size.s340), spacing: skin.size.s14, alignment: .top)],
                    alignment: .leading, spacing: skin.size.s14
                ) {
                    ForEach(Array(model.projects.enumerated()), id: \.element.id) { index, project in
                        ProjectCard(
                            facts: ProjectFacts(
                                project: project, model: model, hasTrancheB: store.hasTrancheB,
                                logo: store.projectLogos.images[project.id]),
                            order: index
                        ) {
                            store.openProject(project.id)
                        }
                    }
                    AddProjectCard(order: model.projects.count) { creating = true }
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.bottom, skin.size.s20)
            }
            .scrollIndicators(.never)
            .offlineDimmed()
        }
    }

    private var notFound: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Project not found", crumb: nil) {
                AinkradButton(title: "‹ Projects", style: .ghost) { store.closeProject() }.compact().fixedSize()
            }
            AinkradEmptyState(icon: "square.grid.2x2", title: "No such project", message: "It may have been archived.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// One project card (`.pc`): tinted glass, lifts on hover, rises in by its order.
private struct ProjectCard: View {
    let facts: ProjectFacts
    let order: Int
    let open: () -> Void
    @State private var hovering = false
    @State private var shown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        let tint = facts.tint
        AinkradTapArea(help: "Open \(facts.project.name)", action: open) {
            VStack(alignment: .leading, spacing: skin.size.s14) {
                top
                middle.frame(minHeight: skin.size.s64)
                team.frame(minHeight: skin.size.s28)
                repos
                health
            }
            .padding(skin.size.s18)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                shape.fill(
                    LinearGradient(
                        stops: [
                            .init(color: tint.0.opacity(skin.opacity.o14), location: 0),
                            .init(color: skin.color(.palette("foreground", skin.opacity.o03)), location: 0.55),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(shape.strokeBorder(tint.0.opacity(hovering ? skin.opacity.o45 : skin.opacity.o25), lineWidth: 1))
            .contentShape(shape)
        }
        .shadow(
            color: skin.color(.palette("black", hovering ? skin.opacity.o35 : 0)), radius: skin.size.s20,
            y: skin.size.s18
        )
        .offset(y: reduceMotion ? 0 : (hovering ? -skin.size.s4 : (shown ? 0 : skin.size.s10)))
        .opacity(shown || reduceMotion ? 1 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.22)), value: hovering)
        .onAppear {
            withAnimation(
                skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.38)).delay(Double(order) * 0.04)
            ) {
                shown = true
            }
        }
    }

    private var top: some View {
        HStack(spacing: skin.size.s12) {
            ProjectMark(glyph: facts.glyph, tint: facts.tint, side: skin.size.s44, logo: facts.logo)
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(facts.project.name).citadelFont("t16", weight: "bold").foregroundStyle(
                    skin.color(skin.text.primary)
                )
                .lineLimit(1)
                (Text(facts.project.key).font(skin.font(AinkradFontToken(sizeKey: "t11", mono: "family")))
                    .foregroundStyle(skin.color(skin.palette.accentSecondary))
                    + Text(
                        [
                            Optional(facts.teams.map(\.name).joined(separator: " + ")).nonEmpty,
                            facts.lead.map { "★ \($0.name)" },
                        ].compactMap { $0 }.map { " · \($0)" }
                            .joined()))
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
            }
            Spacer(minLength: skin.size.s8)
            if let active = facts.active, facts.isScrum {
                AinkradStatePill(text: "Sprint \(active.name)", tint: skin.color(skin.palette.accentSecondary))
            } else {
                AinkradStatePill(text: facts.isScrum ? "No sprint" : "Kanban", tint: skin.color(skin.text.muted))
            }
        }
    }

    @ViewBuilder private var middle: some View {
        if facts.isScrum, let burndown = facts.burndown, let report = facts.report {
            HStack(spacing: skin.size.s14) {
                AinkradRingGauge(
                    value: report.fraction, tint: skin.color(skin.palette.accentSecondary), diameter: skin.size.s64,
                    lineWidth: skin.size.s7
                ) {
                    Text("\(Int(report.fraction * 100))%").citadelFont("t12", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary))
                }
                VStack(alignment: .leading, spacing: skin.size.s4) {
                    BurndownChart(left: burndown.left, committed: report.committed, days: burndown.days)
                        .frame(maxWidth: skin.size.s200, minHeight: skin.size.s50, maxHeight: skin.size.s50)
                    Text(facts.sprintLine ?? "").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                }
            }
        } else {
            let open = facts.work.open.count
            let done = facts.work.items.filter(\.isDone).count
            VStack(alignment: .leading, spacing: skin.size.s8) {
                FlowBar(flow: facts.work.flow)
                Text("\(open) open · \(done) done").citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
            }
            .frame(maxHeight: .infinity)
        }
    }

    private var team: some View {
        HStack(spacing: skin.size.s8) {
            if facts.busy.isEmpty {
                Text("nobody working right now").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            } else {
                HStack(spacing: -skin.size.s6) {
                    ForEach(facts.busy.prefix(4)) { AgentFigure(agent: $0, model: facts.model, size: skin.size.s26) }
                }
                Text("\(facts.busy.count) working now").citadelFont("t11")
                    .foregroundStyle(skin.color(skin.palette.accentSecondary))
                    .padding(.leading, skin.size.s8)
            }
            Spacer(minLength: skin.size.s8)
            HStack(spacing: -skin.size.s5) {
                ForEach(facts.idle.prefix(5)) { AgentFigure(agent: $0, model: facts.model, size: skin.size.s18) }
            }
        }
    }

    @ViewBuilder private var repos: some View {
        if facts.repos.isEmpty {
            Text("no repository · writing only").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        } else {
            AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                ForEach(facts.repos) { RepoChip(name: $0.name) }
            }
        }
    }

    private var health: some View {
        let proposals = facts.profile?.proposals.count ?? 0
        return HStack(spacing: skin.size.s12) {
            if proposals > 0 {
                dot(skin.color(skin.palette.accentViolet), "\(proposals) proposal\(proposals == 1 ? "" : "s")")
            }
            if facts.blocked > 0 { dot(skin.color(skin.palette.danger), "\(facts.blocked) blocked") }
            if let ci = facts.ci {
                dot(skin.color(ci == "CI failing" ? skin.palette.danger : skin.palette.success), ci)
            }
            Spacer(minLength: skin.size.s8)
            Text("\(facts.work.open.count) open").citadelFont("t11", mono: true).foregroundStyle(
                skin.color(skin.text.faint))
        }
        .padding(.top, skin.size.s10)
    }

    private func dot(_ tint: Color, _ text: String) -> some View {
        HStack(spacing: skin.size.s5) {
            Circle().fill(tint).frame(width: skin.size.s7, height: skin.size.s7)
            Text(text).citadelFont("t11").foregroundStyle(tint)
        }
    }
}

/// `⑂ citadel` (`.repo`).
struct RepoChip: View {
    let name: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s4) {
            Text("⑂").citadelFont("t10").foregroundStyle(skin.color(skin.palette.accentSecondary))
            Text(name).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.primary))
        }
        .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
        .background(skin.color(.palette("foreground", skin.opacity.o06)), in: Capsule())
    }
}

/// The dashed "New project" card.
private struct AddProjectCard: View {
    let order: Int
    let create: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        AinkradTapArea(help: "New project", action: create) {
            VStack(spacing: skin.size.s6) {
                Text("＋").citadelFont("t18").foregroundStyle(skin.color(skin.text.muted))
                    .frame(width: skin.size.s40, height: skin.size.s40)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o06)),
                        in: RoundedRectangle(cornerRadius: skin.size.s12))
                Text("New project").citadelFont("t14", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                Text("a team, repos and rules").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            .frame(maxWidth: .infinity, minHeight: skin.size.s260)
            .overlay(
                shape.strokeBorder(
                    hovering
                        ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o45)
                        : skin.color(.palette("foreground", skin.opacity.o14)),
                    style: StrokeStyle(lineWidth: 1, dash: [skin.size.s4, skin.size.s3]))
            )
            .contentShape(shape)
        }
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}
