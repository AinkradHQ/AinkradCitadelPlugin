import AinkradAppKit
import SwiftUI

/// Screen 14: the projects beside the selected one's profile — what every run on it is given (E15.13): agents'
/// proposed changes (never applied without you, decision #48), its repos in merge order (#51, #54), how work is
/// done there, and its limits (#52).
struct ProjectsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var section: ProfileSection? = .repositories
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    private var page: ProjectsPage { model.projectsPage }
    private var project: ProjectInfo? {
        model.projects.first { $0.id == page.selected } ?? model.projects.first
    }

    var body: some View {
        HStack(spacing: 0) {
            list
                .frame(width: skin.size.s220)
                .background(theme.surface.opacity(skin.opacity.o20))
            ScrollViewReader { proxy in
                VStack(alignment: .leading, spacing: 0) {
                    if let project {
                        ProfileHead(model: model, project: project)
                        ScrollView {
                            ProfileBody(store: store, model: model, project: project)
                                .padding(.horizontal, skin.size.s20)
                                .padding(.bottom, skin.size.s20)
                        }
                        .offlineDimmed()
                    } else {
                        PaneTitle(title: "Projects", crumb: nil)
                        AinkradEmptyState(
                            icon: "square.grid.2x2", title: "No projects yet",
                            message: "A project holds its repos, its profile and its limits; agents plan work in one."
                        )
                        .frame(maxWidth: .infinity, maxHeight: .infinity)
                    }
                }
                .onChange(of: section) { _, section in
                    guard let section else { return }
                    withAnimation(skin.animation(skin.motion.present)) { proxy.scrollTo(section, anchor: .top) }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .task { if !page.isLoaded { store.loadProjectsPage() } }
    }

    private var list: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Projects", crumb: nil) {
                // TODO(citadel#createProject): no POST /companies/{id}/projects on the client API yet.
                AinkradIconButton(systemName: "plus", size: skin.size.s30, tooltip: "New project") {}
                    .outlineBox().disabled(true)
            }
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    ForEach(model.projects) { item in
                        AinkradListRow(
                            isSelected: item.id == project?.id, onTap: { store.selectProject(item.id) },
                            leading: { ProjectGlyph(project: item) }, title: item.name, subtitle: page.subtitle(item),
                            trailing: { EmptyView() })
                    }
                    if let project { sectionIndex(project).padding(.top, skin.size.s14) }
                }
                .padding(.horizontal, skin.size.s8)
                .padding(.bottom, skin.size.s12)
            }
        }
    }

    /// "On this page": jumps to a group.
    private func sectionIndex(_ project: ProjectInfo) -> some View {
        let profile = page.profiles[project.id]
        return VStack(alignment: .leading, spacing: skin.size.s4) {
            Text(skin.labelCased("On this page")).citadelFont("t10", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.muted)).padding(.horizontal, skin.size.s10)
            AinkradNavList(
                items: ProfileSection.allCases,
                selection: Binding(get: { section ?? .repositories }, set: { section = $0 }),
                icon: { _ in nil },
                label: {
                    $0.title(
                        proposals: profile?.proposals.count ?? 0, repos: page.repos[project.id]?.count ?? 0,
                        overridden: page.overriddenCount(project.id))
                }
            )
            .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The groups of a profile, in page order: the "On this page" index and the scroll targets.
enum ProfileSection: String, CaseIterable, Hashable {
    case proposals, repositories, done, branches, environments, models, policies, limits, docs

    func title(proposals: Int, repos: Int, overridden: Int) -> String {
        switch self {
        case .proposals: "Proposed changes · \(proposals)"
        case .repositories: "Repositories · \(repos)"
        case .done: "Definition of done"
        case .branches: "Branches & PRs"
        case .environments: "Environments"
        case .models: "Models per role"
        case .policies: "Policies"
        case .limits: "Limits · \(overridden) overridden"
        case .docs: "Docs & links"
        }
    }
}

/// A project's glyph on a tinted square (the mockup's `.pico`): the castle for a project with repos.
struct ProjectGlyph: View {
    let project: ProjectInfo
    var isLarge = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let size = isLarge ? skin.size.s32 : skin.size.s24
        Image(systemName: project.mode == "kanban" ? "rectangle" : "building.columns")
            .font(skin.font(AinkradFontToken(sizeKey: isLarge ? "t15" : "t12")))
            .foregroundStyle(theme.accentSecondary)
            .frame(width: size, height: size)
            .background(
                theme.accentSecondary.opacity(skin.opacity.o10), in: RoundedRectangle(cornerRadius: skin.size.s6)
            )
            .accessibilityHidden(true)
    }
}

/// "⛫ Citadel · project profile / CIT · Citadel Core · edited Oct 22", and the injection meter: how much of the
/// profile budget every run on it is given.
private struct ProfileHead: View {
    let model: CompanyModel
    let project: ProjectInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let profile = model.projectsPage.profiles[project.id]
        HStack(spacing: skin.size.s12) {
            ProjectGlyph(project: project, isLarge: true)
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text("\(project.name) · project profile").citadelFont("t15", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                crumb(profile).citadelFont("t11").lineLimit(1)
            }
            Spacer(minLength: skin.size.s10)
            if let profile, profile.budgetBytes > 0 {
                HStack(spacing: skin.size.s10) {
                    Text("In every run").citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                    AinkradStackedStatusBar(toneRuns: [
                        AinkradToneRun(value: Double(profile.injectedBytes), tone: .accentSecondary),
                        AinkradToneRun(
                            value: Double(max(0, profile.budgetBytes - profile.injectedBytes)), tone: .muted),
                    ])
                    .frame(width: skin.size.s120)
                    Text("\(Fmt.tokens(profile.injectedBytes)) / \(Fmt.tokens(profile.budgetBytes)) bytes")
                        .citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.muted))
                }
                .help("The profile is injected into every run, within the profile budget (a setting, see Limits).")
            }
            // TODO(citadel#profilePreview): no endpoint renders exactly what a run is given yet.
            AinkradIconButton(systemName: "eye", size: skin.size.s30, tooltip: "Preview what a run sees") {}
                .outlineBox().disabled(true)
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.top, skin.size.s14)
        .padding(.bottom, skin.size.s10)
    }

    private func crumb(_ profile: ProfileInfo?) -> Text {
        let faint = skin.color(skin.text.muted)
        let team = model.departments.flatMap(\.teams).first { $0.id == project.teamID }?.name
        var text = Text(project.key).foregroundStyle(theme.accentSecondary)
        for part in [team, profile?.updatedAt.map { "edited \($0.formatted(.dateTime.month(.abbreviated).day()))" }]
            .compactMap({ $0 })
        {
            text = text + Text(" · \(part)").foregroundStyle(faint)
        }
        return text
    }
}
