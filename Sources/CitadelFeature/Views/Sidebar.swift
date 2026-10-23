import AinkradAppKit
import CitadelClient
import SwiftUI

/// The screens the sidebar lists (mockups 02–16), in the mockups' order.
enum Screen: String, CaseIterable, Hashable {
    case home, requirements, approvals, stuck, org, runs, threads, artifacts, projects, cost, accounts, runners

    var title: String {
        switch self {
        case .home: "Home"
        case .requirements: "Requirements"
        case .approvals: "Approvals"
        case .stuck: "Why stuck"
        case .org: "Org"
        case .runs: "Runs"
        case .threads: "Agent threads"
        case .artifacts: "Artifacts"
        case .projects: "Projects"
        case .cost: "Cost"
        case .accounts: "Accounts"
        case .runners: "Runners"
        }
    }

    var icon: String {
        switch self {
        case .home: "scope"
        case .requirements: "rhombus.fill"
        case .approvals: "checkmark"
        case .stuck: "flag.fill"
        case .org: "rhombus"
        case .runs: "play.fill"
        case .threads: "envelope.fill"
        case .artifacts: "doc.text.fill"
        case .projects: "square.grid.2x2.fill"
        case .cost: "dollarsign"
        case .accounts: "person.text.rectangle"
        case .runners: "cylinder.split.1x2.fill"
        }
    }
}

/// Company switcher and settings, search, the screens, and the connection's footer. Told apart from the main pane
/// by fill, never by a line.
struct Sidebar: View {
    @Bindable var store: CitadelStore
    @State private var search = ""
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(spacing: skin.size.s8) {
                AinkradWorkspaceSwitcher(
                    workspaces: store.companies.map(Self.workspace), selection: companySelection,
                    subtitle: switcherSubtitle, header: "Companies on \(store.host)",
                    footnote: "Accounts, runners and cost are per company · switching never mixes data")
                AinkradIconButton(systemName: "gearshape", size: skin.size.s30, tooltip: "Settings") {
                    store.isShowingSettings.toggle()
                }
                .outlineBox()
            }
            AinkradSearchField(text: $search, placeholder: "Search agents, issues, runs").keyHint("⌘K")
            AinkradNavList(items: Screen.allCases, selection: navSelection, icon: { $0.icon }, label: { $0.title })
                .counts { screen in store.model?.navCount(screen) }
                .fixedSize(horizontal: false, vertical: true)
            if let model = store.model, !model.liveRuns.isEmpty { liveNow(model) }
            Spacer(minLength: 0)
            footer
        }
        .padding(.top, skin.size.s12)
        .padding(.horizontal, skin.size.s12)
        .padding(.bottom, skin.size.s10)
        .frame(width: skin.size.s280)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(theme.surface.opacity(skin.opacity.o35))
    }

    private var navSelection: Binding<Screen> {
        Binding(
            get: { store.screen },
            set: {
                store.screen = $0
                store.detail = nil
                store.isShowingSettings = false
            })
    }

    private var companySelection: Binding<String> {
        Binding(
            get: { store.company.map { String($0.id) } ?? "" },
            set: { if let id = Int64($0) { store.select(company: id) } })
    }

    private var switcherSubtitle: String {
        let others = max(0, store.companies.count - 1)
        return others == 0 ? "Citadel" : "Citadel · \(others) other compan\(others == 1 ? "y" : "ies")"
    }

    static func workspace(_ company: Components.Schemas.Company) -> AinkradWorkspace {
        AinkradWorkspace(
            id: String(company.id), name: company.name, kind: company.kind.value1 == .client ? .client : .own)
    }

    /// "Live now": every run in flight, one click from its transcript.
    private func liveNow(_ model: CompanyModel) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            Text(skin.labelCased("Live now")).citadelFont("t10", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.muted))
                .padding(.horizontal, skin.size.s4)
            ForEach(model.liveRuns.prefix(5)) { run in
                LiveNowRow(run: run, model: model) { store.open(.run(run.id)) }
            }
        }
        .padding(.top, skin.size.s16)
    }

    /// `● citadel.ainkrad.io      live · seq 18,442`.
    private var footer: some View {
        let (dot, word) = footerState
        return HStack(spacing: skin.size.s6) {
            Circle().fill(dot).frame(width: skin.size.s7, height: skin.size.s7)
            Text(store.host)
                .font(skin.font(AinkradFontToken(sizeKey: "t11", mono: "family"), typography: typo))
                .foregroundStyle(skin.color(skin.text.muted))
                .lineLimit(1)
                .truncationMode(.middle)
            Spacer(minLength: skin.size.s6)
            Text(word)
                .font(skin.font(AinkradFontToken(sizeKey: "t11"), typography: typo))
                .foregroundStyle(skin.color(skin.text.faint))
                .lineLimit(1)
        }
        .padding(.horizontal, skin.size.s2)
    }

    private var footerState: (Color, String) {
        let seq = store.cursor.map { " · seq \($0.formatted())" } ?? ""
        switch (store.phase, store.streamStatus) {
        case (.offline, _): return (status.warning, "offline · retrying")
        case (.rejected, _): return (status.danger, "key rejected")
        case (_, .catchingUp?): return (theme.accentSecondary, "catching up")
        case (_, .polling?): return (status.warning, "polling\(seq)")
        case (.connected, _): return (status.success, "live\(seq)")
        default: return (skin.color(skin.text.faint), "connecting")
        }
    }
}

private struct LiveNowRow: View {
    let run: RunInfo
    let model: CompanyModel
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let agent = model.agent(run.agentID)
        let issue = model.issue(run.issueID)
        HStack(alignment: .top, spacing: skin.size.s10) {
            Circle().fill(theme.accentSecondary).frame(width: skin.size.s7, height: skin.size.s7)
                .padding(.top, skin.size.s6).breathing(run.state == "running")
            VStack(alignment: .leading, spacing: skin.size.s2) {
                HStack(spacing: skin.size.s6) {
                    Text("\(agent?.name ?? "Agent") · \(issue?.title ?? "run #\(run.id)")").citadelFont("t13")
                        .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                    Spacer(minLength: skin.size.s4)
                    Text(Fmt.age(Date().timeIntervalSince(run.startedAt ?? run.queuedAt))).citadelFont(
                        "t10_5", mono: true
                    )
                    .foregroundStyle(skin.color(skin.text.faint))
                }
                HStack(spacing: skin.size.s6) {
                    AinkradBadge(
                        text: AgentLook.harnessName(run.harness),
                        tint: AgentLook.harness(run.harness)?.color ?? theme.foreground)
                    if let issue {
                        Text(issue.key).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    }
                }
            }
        }
        .padding(.horizontal, skin.size.s4)
        .padding(.vertical, skin.size.s2)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous)
                .fill(skin.color(skin.palette.white).opacity(hovering ? skin.opacity.o05 : 0))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
