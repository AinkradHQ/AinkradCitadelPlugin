import AinkradAppKit
import SwiftUI

/// `#/projects/<KEY>`: the hero, the gliding section bar (Overview · Board · Backlog · Sprints · Timeline ·
/// Reports), the tab, and the drawer (configuration tabs or a work item) floating over it.
struct ProjectPage: View {
    let store: CitadelStore
    let model: CompanyModel
    let project: ProjectInfo
    let newProject: () -> Void
    @Environment(\.ainkradSkin) private var skin

    private var page: ProjectsPage { model.projectsPage }
    private var facts: ProjectFacts { ProjectFacts(project: project, model: model) }

    var body: some View {
        let facts = facts
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s14) {
                ProjectHero(store: store, facts: facts, slim: page.tab != .overview)
                AinkradGlideTabs(
                    tabs(facts), selection: Binding(get: { page.tab }, set: { page.tab = $0 }), tint: facts.tint,
                    height: skin.size.s44)
                tab(facts)
            }
            .padding(.horizontal, skin.size.s20)
            .padding(.top, skin.size.s14)
            .padding(.bottom, skin.size.s20)
        }
        .scrollIndicators(.never)
        .offlineDimmed()
        .floatingInsetDrawer(isPresented: Binding(get: { page.drawer != nil }, set: { if !$0 { page.drawer = nil } })) {
            drawerHeader(facts)
        } content: {
            drawerBody(facts)
        }
        .task(id: project.id) { if page.work[project.id] == nil { store.loadWork(project.id) } }
    }

    private func tabs(_ facts: ProjectFacts) -> [AinkradGlideTab<ProjectTab>] {
        let work = facts.work
        return ProjectTab.allCases.map { tab in
            let count: String? =
                switch tab {
                case .board: work.boardItems.filter(\.isOpen).count.nonZero
                case .backlog: work.backlog.count.nonZero
                case .sprints: work.active?.name
                default: nil
                }
            return AinkradGlideTab(tab, title: tab.title, systemImage: tab.icon, count: count)
        }
    }

    @ViewBuilder private func tab(_ facts: ProjectFacts) -> some View {
        switch page.tab {
        case .overview: ProjectOverview(store: store, facts: facts)
        case .board: ProjectBoard(store: store, facts: facts)
        case .backlog: ProjectBacklog(store: store, facts: facts)
        case .sprints: ProjectSprints(store: store, facts: facts)
        case .timeline: ProjectTimeline(store: store, facts: facts)
        case .reports: ProjectReports(facts: facts)
        }
    }

    @ViewBuilder private func drawerHeader(_ facts: ProjectFacts) -> some View {
        if case .config(let current) = page.drawer {
            AinkradGlideTabs(
                ConfigTab.allCases.map { AinkradGlideTab($0, title: $0.title, systemImage: $0.icon) },
                selection: Binding(get: { current }, set: { page.drawer = .config($0) }), tint: facts.tint)
        } else {
            Text(skin.labelCased("Work item")).citadelFont("t10_5", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.muted)).padding(.leading, skin.size.s6)
        }
    }

    @ViewBuilder private func drawerBody(_ facts: ProjectFacts) -> some View {
        switch page.drawer {
        case .item(let id): WorkItemPanel(store: store, facts: facts, itemID: id)
        case .config(.teams): ConfigTeams(store: store, facts: facts)
        case .config(.repos): ConfigRepos(store: store, facts: facts)
        case .config(.rules): ConfigRules(store: store, facts: facts)
        case .config(.runtime): ConfigRuntime(store: store, facts: facts)
        case .config(.limits): ConfigLimits(store: store, facts: facts)
        case .config(.docs): ConfigDocs(store: store, facts: facts)
        case .config(.context): ConfigContext(facts: facts)
        case nil: EmptyView()
        }
    }
}

extension Int {
    /// `nil` for zero: a tab badge only shows when there is something to count.
    var nonZero: String? { self == 0 ? nil : String(self) }
}
