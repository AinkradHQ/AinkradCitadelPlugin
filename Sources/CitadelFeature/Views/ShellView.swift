import AinkradAppKit
import SwiftUI

/// The window after the first connect: sidebar and the selected screen. The shared states of mockup 11 live here —
/// offline with cached data (B), catching up after a reconnect (C), first load (D).
struct ShellView: View {
    @Bindable var store: CitadelStore
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(store: store)
            VStack(alignment: .leading, spacing: 0) {
                // Mockup 11 B's bar, once for the whole pane and outside every screen's dimmed body: "Retry now"
                // stays live for as long as the server is away, whichever screen (or Settings) is open.
                if isOffline {
                    OfflineBar(store: store).padding(.top, skin.size.s10)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
                ZStack {
                    Group {
                        if store.isShowingSettings {
                            CompanySettingsView(store: store)
                        } else {
                            content.environment(
                                \.citadelOffline, isOffline ? Offline(store: store, crumb: offlineCrumb) : nil)
                        }
                    }
                    .id(store.route)
                    .transition(store.navDirection.transition(skin, reduceMotion: reduceMotion))
                }
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: store.route)
                .clipped()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .overlay(alignment: .bottom) { failureBanner }
            .overlay(alignment: .topTrailing) { AinkradRichToastStack(center: store.toasts) }
        }
        .background { ShellShortcuts(store: store) }
        .overlay {
            if store.isSearching, let model = store.model {
                Spotlight(store: store, model: model, query: store.searchSeed)
            }
        }
        .animation(
            reduceMotion ? nil : skin.animation(skin.motion.present),
            value: store.isSearching
        )
        // The New requirement sheet opens from any screen (Home, Requirements, ⌘N).
        .ainkradPanelModal(isPresented: $store.isComposingRequirement, contentWidth: skin.size.s380 * 2) {
            if let model = store.model { NewRequirementSheet(store: store, model: model) }
        }
        // New company: from the switcher menu and ⌘K.
        .ainkradPanelModal(
            isPresented: $store.isCreatingCompany, contentWidth: skin.size.s860 + skin.size.s200 - skin.size.s48
        ) {
            NewCompanyWizard(store: store)
        }
        .overlay {
            if store.screen == .artifacts, !store.isShowingSettings, let model = store.model,
                let id = model.artifactsPage.quickLookID,
                let artifact = model.artifactsPage.items.first(where: { $0.id == id })
            {
                ArtifactQuickLook(store: store, model: model, artifact: artifact)
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
            }
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: isOffline)
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: store.actionFailure)
        .animation(
            reduceMotion ? nil : skin.animation(skin.motion.present), value: store.model?.artifactsPage.quickLookID)
    }

    /// Mockup 11 G away from the inbox (which shows it in place of the approval): what the server refused, said
    /// once, with Copy error.
    @ViewBuilder private var failureBanner: some View {
        if let failure = store.actionFailure, store.screen != .approvals || store.detail != nil {
            AinkradBanner(
                message: "\(failure.title). \(failure.message)", status: .danger, actionTitle: "Copy error",
                action: { failure.answer.copy() }, onDismiss: { store.actionFailure = nil }
            )
            .padding(skin.size.s14)
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    private var isOffline: Bool {
        if case .offline = store.phase { true } else { false }
    }

    /// "◌ offline · showing data from 3 min ago".
    private var offlineCrumb: Text? {
        guard isOffline else { return nil }
        let minutes = store.settings.document.lastSeen.map { Int(Date().timeIntervalSince($0) / 60) } ?? 0
        let age = minutes < 1 ? "just now" : "\(minutes) min ago"
        return Text("◌ offline · showing data from \(age)").foregroundStyle(status.warning)
    }

    @ViewBuilder
    private var content: some View {
        if case .catchingUp(let replayed) = store.streamStatus {
            VStack(spacing: 0) {
                PaneTitle(title: store.company?.name ?? CitadelApp.displayName, crumb: nil)
                CatchingUpView(replayed: replayed, total: store.catchUpTotal)
            }
        } else if let model = store.model, model.isLoaded {
            screenView(model)
        } else if !isOffline {
            VStack(spacing: 0) {
                PaneTitle(title: store.company?.name ?? CitadelApp.displayName, crumb: nil)
                FirstLoadView()
            }
        } else {
            placeholder
        }
    }

    @ViewBuilder
    private func screenView(_ model: CompanyModel) -> some View {
        // 11 E: a company with no agents shows its onboarding on every screen but the ones that set it up.
        if model.agents.isEmpty, ![.accounts, .runners].contains(store.screen), store.detail == nil {
            NoAgentsView(store: store, model: model)
        } else {
            routed(model)
        }
    }

    @ViewBuilder
    private func routed(_ model: CompanyModel) -> some View {
        switch (store.detail, store.screen) {
        case (.agent(let id)?, _): AgentView(store: store, model: model, agentID: id)
        case (.run(let id)?, _): RunView(store: store, model: model, runID: id)
        case (nil, .home): HomeView(store: store, model: model)
        case (nil, .org): OrgView(store: store, model: model)
        case (nil, .approvals): ApprovalsView(store: store, model: model)
        case (nil, .threads): ThreadsView(store: store, model: model)
        case (nil, .stuck): StuckView(store: store, model: model)
        case (nil, .cost): CostView(store: store, model: model)
        case (nil, .requirements): RequirementsView(store: store, model: model)
        case (nil, .artifacts): ArtifactsView(store: store, model: model)
        case (nil, .projects): ProjectsView(store: store, model: model)
        case (nil, .accounts): AccountsView(store: store, model: model)
        case (nil, .runners): RunnersView(store: store, model: model)
        case (nil, .runs): RunsView(store: store, model: model)
        default: placeholder
        }
    }

    private var placeholder: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: store.company?.name ?? CitadelApp.displayName, crumb: nil)
            AinkradEmptyState(
                icon: store.screen.icon, title: store.screen.title,
                message: "Nothing is cached for this screen yet; it fills in as soon as the server answers."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .offlineDimmed()
        }
    }
}

/// Mockup 11 B, handed to every screen: its title shows the offline crumb and the amber bar, and the screen's
/// cached data below dims.
struct Offline {
    let store: CitadelStore
    let crumb: Text?
}

extension EnvironmentValues {
    @Entry var citadelOffline: Offline? = nil
}

/// The main pane's title row: the title, an optional crumb under it, actions on the right. Offline, the crumb says
/// so (the shell draws the amber bar above the pane), and the rest of the screen (`dimmed`) fades.
struct PaneTitle<Trailing: View>: View {
    let title: String
    let crumb: Text?
    let trailing: Trailing
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.citadelOffline) private var offline

    init(title: String, crumb: Text?, @ViewBuilder trailing: () -> Trailing) {
        self.title = title
        self.crumb = crumb
        self.trailing = trailing()
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(alignment: .top, spacing: skin.size.s10) {
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text(title)
                        .font(skin.font(AinkradFontToken(sizeKey: "t15", weight: "semibold"), typography: typo))
                        .foregroundStyle(skin.color(skin.text.primary))
                        .lineLimit(1)
                    if let crumb = offline?.crumb ?? crumb {
                        crumb.font(skin.font(AinkradFontToken(sizeKey: "t11"), typography: typo)).lineLimit(1)
                    }
                }
                Spacer(minLength: skin.size.s10)
                trailing
            }
            .padding(.horizontal, skin.size.s20)
            .padding(.top, skin.size.s14)
            .padding(.bottom, skin.size.s10)
        }
    }
}

extension PaneTitle where Trailing == EmptyView {
    init(title: String, crumb: Text?) {
        self.init(title: title, crumb: crumb) { EmptyView() }
    }
}

extension View {
    /// A screen's body below its title: dimmed and inert while offline (mockup 11 B).
    func offlineDimmed() -> some View { modifier(OfflineDimmed()) }
}

private struct OfflineDimmed: ViewModifier {
    @Environment(\.citadelOffline) private var offline
    @Environment(\.ainkradSkin) private var skin

    func body(content: Content) -> some View {
        content
            .saturation(offline == nil ? 1 : skin.opacity.o55)
            .brightness(offline == nil ? 0 : -skin.opacity.o20)
            .allowsHitTesting(offline == nil)
    }
}
