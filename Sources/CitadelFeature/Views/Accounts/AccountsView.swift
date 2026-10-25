import AinkradAppKit
import CitadelClient
import SwiftUI

/// Which inset drawer the Accounts screen shows.
enum AccountDrawer: Equatable {
    case limits(Int64)
    case relogin(Int64)
    case add
    case chain(String)
}

/// Screen 15 (prototype `accounts.js`): the pool overview (health donut, headroom per harness, who is on the pool),
/// the account cards with rings and actions, the fallback chains (shared chains and per agent) and the last
/// fallbacks; Limits, Re-login and Add account open as inset drawers.
struct AccountsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: AccountsPage { model.accountsPage }

    var body: some View {
        let accounts = page.visible(company: model.companyID)
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(
                title: "Accounts",
                crumb: Text("provider account pool · owned by you").foregroundStyle(skin.color(skin.text.muted))
            ) { trailing }
            ScrollView {
                if !page.isLoaded {
                    FirstLoadView()
                } else {
                    VStack(alignment: .leading, spacing: skin.size.s12) {
                        if page.showsWholePool { WholePoolNote().transition(.opacity) }
                        AccountsOverview(model: model, accounts: accounts)
                        HStack(alignment: .top, spacing: skin.size.s14) {
                            cards(accounts).frame(maxWidth: .infinity)
                            VStack(spacing: skin.size.s12) {
                                FallbackChainsCard(store: store, model: model) { page.drawer = .chain($0) }
                                LastFallbacksTile(store: store, model: model)
                            }
                            .frame(width: skin.size.s380)
                        }
                    }
                    .padding(.horizontal, skin.size.s20)
                    .padding(.bottom, skin.size.s20)
                    .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: accounts)
                }
            }
            .scrollIndicators(.never)
            .offlineDimmed()
        }
        .opsDrawer(isPresented: Binding(get: { page.drawer != nil }, set: { if !$0 { page.drawer = nil } })) {
            drawerPanel
        }
        .task { store.loadAccountsPage() }
        // An account event reloads `model.accounts`; the page follows it (pushed, never polled).
        .onChange(of: model.accounts) { _, _ in if page.isLoaded { store.loadAccountsPage() } }
    }

    @ViewBuilder private var drawerPanel: some View {
        let close = { page.drawer = nil }
        switch page.drawer {
        case .limits(let id):
            if let account = page.accounts.first(where: { $0.id == id }) {
                AccountLimitsDrawer(store: store, page: page, account: account, close: close)
            }
        case .relogin(let id):
            if let account = page.accounts.first(where: { $0.id == id }) {
                ReloginDrawer(store: store, page: page, account: account, close: close)
            }
        case .add: AddAccountSheet(store: store, page: page, isPresented: Binding(get: { true }, set: { _ in close() }))
        case .chain(let id):
            if let chain = page.sharedChains(Array(model.agents.values)).first(where: { $0.id == id }) {
                SharedChainDrawer(store: store, model: model, chain: chain, close: close)
            }
        case nil: EmptyView()
        }
    }

    private func cards(_ accounts: [PoolAccount]) -> some View {
        Group {
            if accounts.isEmpty {
                AinkradEmptyState(
                    icon: "person.text.rectangle", title: "No accounts for this company",
                    message: "Assign a pool account to it; its runs use only the accounts it is given."
                )
                .padding(.top, skin.size.s40)
            } else {
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: skin.size.s320), spacing: skin.size.s12, alignment: .top)],
                    alignment: .leading, spacing: skin.size.s12
                ) {
                    ForEach(Array(accounts.enumerated()), id: \.element.id) { index, account in
                        AccountCard(store: store, model: model, account: account, index: index) { page.drawer = $0 }
                    }
                }
            }
        }
    }

    private var trailing: some View {
        HStack(spacing: skin.size.s8) {
            AinkradDockButton(
                "Used by \(store.company?.name ?? "this company")", tone: page.showsWholePool ? .plain : .primary
            ) {
                page.showsWholePool = false
            }
            AinkradDockButton(
                "Whole pool", tone: page.showsWholePool ? .primary : .plain, isEnabled: page.canSeeWholePool
            ) {
                page.showsWholePool = true
            }
            AinkradDockButton("Add account", systemImage: "plus", tone: .primary) {
                page.addFailure = nil
                page.drawer = .add
            }
        }
    }
}

/// "Whole pool · admin view." — the note above the overview in pool scope.
private struct WholePoolNote: View {
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let blue = skin.color(skin.palette.accentPrimary)
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        HStack(spacing: skin.size.s12) {
            Image(systemName: "info.circle").citadelFont("t13").foregroundStyle(blue)
                .frame(width: skin.size.s30, height: skin.size.s30)
                .background(blue.opacity(skin.opacity.o16), in: RoundedRectangle(cornerRadius: skin.size.s9))
            (Text("Whole pool · admin view. ").bold().foregroundStyle(skin.color(skin.text.primary))
                + Text("Includes accounts only other companies use; usage stays attributed per company."))
                .citadelFont("t12_5").foregroundStyle(skin.color(skin.text.muted))
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.vertical, skin.size.s10)
        .background(shape.fill(blue.opacity(skin.opacity.o08)))
        .overlay(shape.strokeBorder(blue.opacity(skin.opacity.o20), lineWidth: 1))
    }
}

/// The newest fallbacks seen on the stream: figure, "#429 Kestrel · CIT-65", "gpt-5.5 → **Opus 5.5**", the reason.
struct LastFallbacksTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let page = model.accountsPage
        let moves = FallbackMove.merged(events: store.recentEvents, runs: page.fallbackRuns)
        BentoTile {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                HStack {
                    Text("Last fallbacks").citadelFont("t13", weight: "bold").foregroundStyle(
                        skin.color(skin.text.primary))
                    Spacer()
                    AinkradTapArea(action: { store.screen = .runs }) {
                        Text("All runs ›").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    }
                }
                if moves.isEmpty {
                    Text("No recent run has fallen back.").citadelFont("t12").foregroundStyle(
                        skin.color(skin.text.faint))
                }
                ForEach(moves.prefix(page.showsAllFallbacks ? moves.count : 4), id: \.run) { move in
                    row(move)
                }
            }
        }
    }

    private func row(_ move: FallbackMove) -> some View {
        let run = model.runs[move.run]
        let agent = model.agent(run?.agentID)
        return AinkradTapArea(action: { store.open(.run(move.run)) }) {
            HStack(alignment: .top, spacing: skin.size.s10) {
                if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s26) }
                VStack(alignment: .leading, spacing: skin.size.s3) {
                    (Text("#\(move.run)").foregroundStyle(theme.accentSecondary)
                        .font(skin.font(AinkradFontToken(sizeKey: "t12", mono: "family")))
                        + Text(heading(agent: agent, run: run)).foregroundStyle(skin.color(skin.text.primary)))
                    HStack(spacing: skin.size.s6) {
                        Text(move.from ?? "—").foregroundStyle(skin.color(skin.text.muted))
                        Text("→").foregroundStyle(theme.accentSecondary)
                        Text(move.to).bold().foregroundStyle(skin.color(skin.text.primary))
                    }
                    if let why = move.why {
                        Text(why).citadelFont("t11").foregroundStyle(skin.color(skin.palette.warning))
                    }
                }
                Spacer(minLength: 0)
            }
            .citadelFont("t12")
            .padding(skin.size.s10)
            .background(
                skin.color(.palette("foreground", skin.opacity.o03)),
                in: RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
            )
            .ainkradHoverLift(0, cornerRadius: skin.size.s12)
        }
    }

    /// " Kestrel · CIT-65".
    private func heading(agent: AgentInfo?, run: RunInfo?) -> String {
        let parts = [agent?.name, model.issue(run?.issueID)?.key].compactMap { $0 }
        return parts.isEmpty ? "" : " " + parts.joined(separator: " · ")
    }
}

/// One run that fell back: from a `run.fallback` event (with what it left), or from the runs list.
struct FallbackMove: Equatable {
    var run: Int64
    /// What it left; the runs list only says where it went.
    var from: String?
    var to: String
    var why: String?

    /// Newest first, from the events the stream delivered since connecting.
    static func recent(_ events: [Components.Schemas.Event]) -> [FallbackMove] {
        events.reversed().compactMap { event in
            guard case .audit(let audit) = event.payload, audit.action == "run.fallback", let run = audit.runId
            else { return nil }
            let details = flatFields(audit.details.value)
            return FallbackMove(
                run: run, from: details["from.model"] ?? details["from.harness"] ?? "?",
                to: details["to.model"] ?? details["to.harness"] ?? "?",
                why: details["reason"] ?? details["class"])
        }
    }

    /// The stream's moves first, then the runs list's fallen-back runs it did not cover, newest first; one per run.
    static func merged(events: [Components.Schemas.Event], runs: [RunInfo]) -> [FallbackMove] {
        var moves: [FallbackMove] = []
        for move in recent(events) where !moves.contains(where: { $0.run == move.run }) { moves.append(move) }
        for run in runs.sorted(by: { $0.id > $1.id }) where !moves.contains(where: { $0.run == run.id }) {
            moves.append(
                FallbackMove(
                    run: run.id, from: nil, to: run.model ?? AgentLook.harnessName(run.harness),
                    why: run.fallbackReason))
        }
        return moves
    }
}
