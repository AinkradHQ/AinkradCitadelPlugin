import AinkradAppKit
import CitadelClient
import SwiftUI

/// The screens the sidebar lists, in the prototype's order (`shell.js` NAV): ⌘1…⌘9 follow it.
enum Screen: String, CaseIterable, Hashable {
    case home, approvals, stuck, requirements, runs, threads, artifacts, org, projects, cost, accounts, runners

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

    /// Line icons in one family, as the prototype's stroked set.
    var icon: String {
        switch self {
        case .home: "house"
        case .approvals: "checkmark.circle"
        case .stuck: "flag"
        case .requirements: "doc.text"
        case .runs: "play.circle"
        case .threads: "bubble.left"
        case .artifacts: "square.3.layers.3d"
        case .org: "point.3.connected.trianglepath.dotted"
        case .projects: "folder"
        case .cost: "chart.bar"
        case .accounts: "key"
        case .runners: "server.rack"
        }
    }

    /// The labelled group a row belongs to; Home stands alone.
    var section: String? {
        switch self {
        case .home: nil
        case .approvals, .stuck: "Needs you"
        case .requirements, .runs, .threads, .artifacts: "Work"
        case .org, .projects: "Company"
        case .cost, .accounts, .runners: "Operations"
        }
    }
}

/// One continuous glass column (no band, no line): the company card, the grouped screens with one gliding pill,
/// what is live now, and the connection with search and settings at the foot.
struct Sidebar: View {
    @Bindable var store: CitadelStore
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            CompanySwitcher(store: store)
                .padding(.top, skin.size.s12)
                .padding(.horizontal, skin.size.s10)
                .padding(.bottom, skin.size.s8)
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 0) {
                    // Optional rows so Settings can select none of them; every row is a screen.
                    AinkradNavList(
                        items: Screen.allCases.map(Optional.some), selection: navSelection, icon: { $0?.icon },
                        label: { $0?.title ?? "" }
                    )
                    .counts { screen in screen.flatMap { store.model?.navCount($0) } }
                    .sections { $0?.section }
                    .glidingSelection()
                    .padding(.horizontal, skin.size.s8)
                    if let model = store.model, !model.liveRuns.isEmpty, !isOffline { liveNow(model) }
                }
            }
            .scrollIndicators(.never)
            footer
        }
        .frame(width: skin.size.s220 + skin.size.s8)
        .frame(maxHeight: .infinity, alignment: .top)
        .background(skin.color(.palette("foreground", skin.opacity.o03)))
    }

    private var isOffline: Bool {
        if case .offline = store.phase { true } else { false }
    }

    /// The screen the pane shows: an opened run sits under Runs, an opened agent under Org, and Settings under none.
    private var navSelection: Binding<Screen?> {
        Binding(
            get: { store.isShowingSettings ? nil : store.detail?.screen ?? store.screen },
            set: {
                guard let screen = $0 else { return }
                store.screen = screen
                store.detail = nil
                store.isShowingSettings = false
            })
    }

    /// "Live now": up to four runs in flight, one click from their transcript.
    private func liveNow(_ model: CompanyModel) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s1) {
            Text("Live now").citadelFont("t10_5", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.faint))
                .padding(.top, skin.size.s14)
                .padding(.bottom, skin.size.s5)
                .padding(.leading, skin.size.s20)
            ForEach(model.liveRuns.prefix(4)) { run in
                LiveNowRow(run: run, model: model) { store.open(.run(run.id)) }
                    .padding(.horizontal, skin.size.s8)
            }
        }
    }

    /// `● Connected` (→ Runners) · search · settings.
    private var footer: some View {
        HStack(spacing: skin.size.s4) {
            HStack(spacing: skin.size.s6) {
                Circle().fill(footerState.0).frame(width: skin.size.s7, height: skin.size.s7)
                Text(footerState.1).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            }
            .padding(.horizontal, skin.size.s6)
            .padding(.vertical, skin.size.s4)
            .homeHoverRow {  // TODO(appkit-A3)
                store.screen = .runners
                store.detail = nil
                store.isShowingSettings = false
            }
            .help("\(store.host) · \(store.cursor.map { "seq \($0.formatted())" } ?? "")")
            Spacer(minLength: skin.size.s4)
            FootButton(icon: "magnifyingglass", tip: "Search · ⌘K", isOn: store.isSearching) {
                store.isSearching = true
            }
            FootButton(icon: "gearshape", tip: "Company settings", isOn: store.isShowingSettings) {
                store.isShowingSettings.toggle()
            }
        }
        .padding(.top, skin.size.s8)
        .padding(.leading, skin.size.s18)
        .padding(.trailing, skin.size.s10)
        .padding(.bottom, skin.size.s10)
    }

    private var footerState: (Color, String) {
        switch (store.phase, store.streamStatus) {
        case (.offline, _): (status.warning, "Offline · retrying")
        case (.rejected, _): (status.danger, "Key rejected")
        case (_, .catchingUp?): (skin.color(skin.palette.accentSecondary), "Catching up")
        case (_, .polling?): (status.warning, "Polling")
        case (.connected, _): (status.success, "Connected")
        default: (skin.color(skin.text.faint), "Connecting")
        }
    }
}

/// A 28 pt footer icon button; `isOn` marks the open surface.
private struct FootButton: View {
    let icon: String
    let tip: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(action: action) {
            Image(systemName: icon).citadelFont("t13")
                .foregroundStyle(skin.color(hovering || isOn ? skin.text.primary : skin.text.muted))
                .frame(width: skin.size.s28, height: skin.size.s28)
                .background(
                    RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous)
                        .fill(
                            isOn
                                ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o20)
                                : skin.color(.palette("foreground", hovering ? skin.opacity.o07 : 0))))
        }
        .buttonStyle(.plain)
        .help(tip)
        .onHover { hovering = $0 }
    }
}

/// `[orb] Kestrel · Event stream replay   4m` over `CIT-42 ▸ Edit crates/…`.
private struct LiveNowRow: View {
    let run: RunInfo
    let model: CompanyModel
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let agent = model.agent(run.agentID)
        let issue = model.issue(run.issueID)
        let tone = model.cardState(of: run).tone
        HStack(alignment: .top, spacing: skin.size.s8) {
            if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s20) }
            VStack(alignment: .leading, spacing: skin.size.s1) {
                HStack(spacing: skin.size.s6) {
                    Text("\(agent?.name ?? "Agent") · \(issue?.title ?? model.runTitle(run))").citadelFont("t12")
                        .foregroundStyle(
                            tone == .danger
                                ? status.danger
                                : tone == .warning ? skin.color(skin.palette.warning) : skin.color(skin.text.primary)
                        )
                        .lineLimit(1)
                    Spacer(minLength: skin.size.s4)
                    TimelineView(.periodic(from: .now, by: 1)) { context in
                        Text(Fmt.age(context.date.timeIntervalSince(run.startedAt ?? run.queuedAt)))
                            .citadelFont("t10", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    }
                }
                HStack(spacing: skin.size.s5) {
                    if let issue {
                        Text(issue.key).citadelFont("t10", mono: true)
                            .foregroundStyle(skin.color(skin.palette.accentSecondary))
                    }
                    Text("▸ \(model.toolNow[run.id] ?? run.state)").citadelFont("t10", mono: true)
                        .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
            }
        }
        .padding(.horizontal, skin.size.s10)
        .padding(.vertical, skin.size.s6)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous)
                .fill(skin.color(.palette("foreground", hovering ? skin.opacity.o05 : 0)))
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .onTapGesture(perform: open)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }
}
