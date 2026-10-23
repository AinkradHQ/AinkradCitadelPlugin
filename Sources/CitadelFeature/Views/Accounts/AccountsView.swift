import AinkradAppKit
import CitadelClient
import SwiftUI

/// Screen 15: the pool of provider accounts (decision #41) — each card with its windows, companies, drops and
/// why it is skipped — the Limits tile for the picked account, and an agent's fallback chain beside them.
struct AccountsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var adding = false

    private var page: AccountsPage { model.accountsPage }

    var body: some View {
        let accounts = page.visible(company: model.companyID)
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Accounts", crumb: crumb(accounts)) { trailing }
            ScrollView {
                if !page.isLoaded {
                    FirstLoadView()
                } else {
                    HStack(alignment: .top, spacing: skin.size.s14) {
                        VStack(spacing: skin.size.s10) {
                            if accounts.isEmpty {
                                AinkradEmptyState(
                                    icon: "person.text.rectangle", title: "No accounts for this company",
                                    message: "Assign a pool account to it; its runs use only the accounts it is given."
                                )
                                .padding(.top, skin.size.s40)
                            }
                            ForEach(accounts) { account in
                                AccountCard(store: store, model: model, account: account)
                            }
                            if !accounts.isEmpty { AccountLimitsTile(store: store, model: model, accounts: accounts) }
                        }
                        .frame(maxWidth: .infinity)
                        VStack(spacing: skin.size.s12) {
                            FallbackChainTile(store: store, model: model)
                            LastFallbacksTile(store: store, model: model)
                        }
                        .frame(width: skin.size.s320)
                    }
                    .padding(.horizontal, skin.size.s20)
                    .padding(.bottom, skin.size.s20)
                    .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: accounts)
                }
            }
            .offlineDimmed()
        }
        .task { store.loadAccountsPage() }
        // An account event reloads `model.accounts`; the page follows it (pushed, never polled).
        .onChange(of: model.accounts) { _, _ in if page.isLoaded { store.loadAccountsPage() } }
    }

    private var trailing: some View {
        HStack(spacing: skin.size.s8) {
            AinkradSegmentedPicker(
                items: [false, true],
                selection: Binding(get: { page.showsWholePool }, set: { page.showsWholePool = $0 }),
                label: { $0 ? "Whole pool" : "Used by \(store.company?.name ?? "this company")" }
            )
            .disabledOptions { $0 && !page.canSeeWholePool }
            .fixedSize()
            AinkradButton(title: "+ Add account", style: .secondary) { adding = true }
                .secondaryAccent().compact().fixedSize()
                .ainkradSheet(isPresented: $adding) { AddAccountSheet(store: store, page: page, isPresented: $adding) }
        }
    }

    /// `pool owned by you · 5 accounts · 3 healthy · 1 at limit · 1 flaky`.
    private func crumb(_ accounts: [PoolAccount]) -> Text {
        let muted = skin.color(skin.text.muted)
        let dot = Text(verbatim: " · ").foregroundStyle(muted)
        func count(_ health: PoolAccount.Health) -> Int { accounts.filter { $0.health == health }.count }
        var text =
            Text("pool owned by you").foregroundStyle(muted) + dot
            + Text("\(accounts.count) account\(accounts.count == 1 ? "" : "s")").foregroundStyle(muted)
        let parts: [(PoolAccount.Health, Color)] = [
            (.healthy, status.success), (.atLimit, status.warning), (.flaky, status.danger),
            (.unhealthy, status.danger),
        ]
        for (health, color) in parts where count(health) > 0 {
            text = text + dot + Text("\(count(health)) \(health.rawValue)").foregroundStyle(color)
        }
        return text
    }
}

/// An agent's chain: its own (harness, model) first, then its fallbacks — drag to reorder, ✕ to remove, the entry
/// in use marked "now"; and what makes a run fall back.
private struct FallbackChainTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    private var page: AccountsPage { model.accountsPage }

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                HStack(spacing: skin.size.s8) {
                    TileHead(title: "Fallback chain")
                    agentPicker
                }
                AinkradReorderList(
                    items: Binding(get: { page.chain }, set: { store.saveChain($0) }), isNumbered: true,
                    current: current
                ) { entry in
                    row(entry)
                }
                addFallback
                Text(skin.labelCased("Fall back when")).citadelFont("t10", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.muted)).padding(.top, skin.size.s4)
                // The server falls back on exactly these (E15.3); they are not settings yet.
                VStack(alignment: .leading, spacing: skin.size.s6) {
                    HStack(spacing: skin.size.s6) {
                        AinkradChip(label: "✓ rate-limited").fixedSize()
                        AinkradChip(label: "✓ out of quota").fixedSize()
                    }
                    AinkradChip(label: "✓ model unavailable").fixedSize()
                }
                .ainkradTooltip("Set by the server: a turn that fails as unavailable, rate-limited or out of quota")
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder private var agentPicker: some View {
        let agents = model.agents.values.sorted { $0.name < $1.name }
        if let selected = page.chainAgent ?? agents.first?.id {
            AinkradSelect(
                items: agents.map(\.id),
                selection: Binding(get: { selected }, set: { store.showChain(of: $0) }),
                label: { model.agent($0).map { "\($0.name) · \($0.role)" } ?? "Agent" }
            )
            .fixedSize()
        }
    }

    /// The entry the agent's live run is on now.
    private var current: FallbackEntry.ID? {
        guard let agent = page.chainAgent, let run = model.liveRuns.first(where: { $0.agentID == agent }) else {
            return nil
        }
        return "\(run.harness)|\(run.model ?? "")"
    }

    private func row(_ entry: FallbackEntry) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s2) {
            HStack(spacing: skin.size.s6) {
                AinkradBadge(
                    text: AgentLook.harnessName(entry.harness),
                    tint: AgentLook.harness(entry.harness)?.color ?? theme.foreground)
                Text(entry.model).citadelFont("t13").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                Spacer(minLength: skin.size.s4)
                if entry.id == current {
                    AinkradBadge(text: "now", tint: theme.accentSecondary)
                } else if !entry.isOwn {
                    AinkradIconButton(systemName: "xmark", size: skin.size.s20, tooltip: "Remove from the chain") {
                        store.saveChain(page.chain.filter { $0.id != entry.id })
                    }
                }
            }
            Text(entry.isOwn ? "the agent's own harness and model" : "account: pool")
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        }
    }

    /// "+ Add fallback": a (harness, model) another agent of the company runs on.
    @ViewBuilder private var addFallback: some View {
        let used = Set(page.chain.map(\.id))
        let candidates = Set(model.agents.values.map { "\($0.harness)|\($0.model)" }).subtracting(used).sorted()
        AinkradMenuButton(
            items: candidates.map { id in
                let parts = id.split(separator: "|", maxSplits: 1).map(String.init)
                return AinkradMenuItem(
                    title: "\(AgentLook.harnessName(parts[0])) · \(parts.last ?? "")", systemName: nil
                ) {
                    store.saveChain(page.chain + [FallbackEntry(harness: parts[0], model: parts.last ?? "")])
                }
            }
        ) { Text("+ Add fallback") }
        .disabled(candidates.isEmpty || page.chainAgent == nil)
    }
}

/// The newest fallbacks seen on the stream: which run moved, from what to what, and why.
private struct LastFallbacksTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let page = model.accountsPage
        let moves = FallbackMove.merged(events: store.recentEvents, runs: page.fallbackRuns)
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                TileHead(
                    title: "Last fallbacks",
                    action: moves.count > 4 ? (page.showsAllFallbacks ? "Newest" : "All \(moves.count) →") : nil
                ) { page.showsAllFallbacks.toggle() }
                if moves.isEmpty {
                    Text("No recent run has fallen back.").citadelFont("t12")
                        .foregroundStyle(skin.color(skin.text.faint))
                }
                ForEach(moves.prefix(page.showsAllFallbacks ? moves.count : 4), id: \.run) { move in
                    VStack(alignment: .leading, spacing: skin.size.s2) {
                        (Text("run #\(move.run)").foregroundStyle(theme.accentSecondary).font(
                            skin.font(AinkradFontToken(sizeKey: "t12", mono: "family")))
                            + Text(heading(move)).foregroundStyle(skin.color(skin.text.muted)))
                        (Text(move.from.map { "\($0) → " } ?? "→ ").foregroundStyle(skin.color(skin.text.primary))
                            + Text(move.to).bold().foregroundStyle(skin.color(skin.text.primary))
                            + Text(move.why.map { " · \($0)" } ?? "").foregroundStyle(status.warning))
                    }
                    .citadelFont("t12")
                    .padding(.horizontal, skin.size.s10)
                    .padding(.vertical, skin.size.s8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        skin.color(skin.palette.white).opacity(skin.opacity.o05),
                        in: RoundedRectangle(cornerRadius: skin.size.s8)
                    )
                    .contentShape(Rectangle())
                    .onTapGesture { store.open(.run(move.run)) }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// " · Kestrel · CIT-65".
    private func heading(_ move: FallbackMove) -> String {
        let run = model.runs[move.run]
        let parts = [model.agent(run?.agentID)?.name, model.issue(run?.issueID)?.key].compactMap { $0 }
        return parts.isEmpty ? "" : " · " + parts.joined(separator: " · ")
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
