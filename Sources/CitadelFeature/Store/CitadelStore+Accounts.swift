import Foundation

/// Screen 15: the account pool, its limits (`account:<id>`, decision #56) and agents' fallback chains.
extension CitadelStore {
    /// The screen opened, or an account event moved `model.accounts`: read everything it shows.
    func loadAccountsPage() {
        guard let server, let model else { return }
        Task { await fillAccounts(model, server: server) }
    }

    /// Sets an account limit typed in the Limits tile; refused input never reaches the server.
    func setAccountSetting(_ account: Int64, key: String, text: String) {
        guard let server, let page = model?.accountsPage, let setting = page.settings[account]?[key],
            let value = setting.parse(text), setting.accepts(text)
        else { return }
        Task {
            if let updated = await server.setSetting(scope: "account:\(account)", key: key, value: value) {
                page.settings[account, default: [:]][key] = updated
            }
        }
    }

    /// ↺: back to the server's value.
    func resetAccountSetting(_ account: Int64, key: String) {
        guard let server, let page = model?.accountsPage else { return }
        Task {
            if let updated = await server.resetSetting(scope: "account:\(account)", key: key) {
                page.settings[account, default: [:]][key] = updated
            }
        }
    }

    /// A counted window typed as "5 h ≤ 3M tok": replaces `old` (cleared first when its length or unit changed).
    func setAccountWindow(_ account: Int64, replacing old: AccountLimitInfo?, text: String) {
        guard let server, let model, let window = AccountLimitInfo.parse(text) else { return }
        Task {
            if let old, old.windowSecs != window.windowSecs || old.unit != window.unit {
                _ = await server.clearAccountLimit(account, windowSecs: old.windowSecs, unit: old.unit)
            }
            _ = await server.setAccountLimit(
                account, windowSecs: window.windowSecs, max: window.max, unit: window.unit)
            await fillAccounts(model, server: server)
        }
    }

    /// ↺ on a counted window: the account goes back to the harness's own signal for it.
    func clearAccountWindow(_ account: Int64, _ limit: AccountLimitInfo) {
        guard let server, let model else { return }
        Task {
            _ = await server.clearAccountLimit(account, windowSecs: limit.windowSecs, unit: limit.unit)
            await fillAccounts(model, server: server)
        }
    }

    /// Shows an agent's chain: its own (harness, model), then its fallbacks.
    func showChain(of agent: Int64) {
        guard let server, let model else { return }
        let page = model.accountsPage
        page.chainAgent = agent
        Task { await loadChain(agent, page: page, model: model, server: server) }
    }

    /// A drag, a removal or an addition: the agent's own entry stays first, the rest is stored in this order.
    func saveChain(_ entries: [FallbackEntry]) {
        guard let server, let model, let agent = model.accountsPage.chainAgent else { return }
        let page = model.accountsPage
        let ordered = FallbackEntry.reordered(entries)
        page.chain = ordered
        Task {
            if let stored = await server.setFallbacks(agent: agent, ordered) {
                page.chain = ordered.filter(\.isOwn) + stored
            }
        }
    }

    /// "+ Add account": sends a checked draft; the new account joins the pool, assigned to no company yet.
    /// Returns at once; `done` runs when the server took it.
    func addAccount(_ draft: NewAccountDraft, done: @escaping @MainActor () -> Void) {
        guard draft.problem == nil, let server, let model else { return }
        let page = model.accountsPage
        page.addProblem = nil
        Task {
            switch await server.createAccount(draft) {
            case .success(let account):
                page.accounts.append(account)
                done()
                await fillAccounts(model, server: server)
            case .failure(let answer):
                page.addProblem =
                    ActionFailure(
                        title: "Couldn't add \(draft.label)", answer: answer, outcome: "No account was added."
                    ).message
            }
        }
    }

    private func fillAccounts(_ model: CompanyModel, server: CitadelServer) async {
        let page = model.accountsPage
        if let pool = await server.poolUsage() {
            page.accounts = pool
            page.canSeeWholePool = true
        } else if let own = await server.companyAccounts() {
            page.accounts = own
            page.canSeeWholePool = false
            page.showsWholePool = false
        }
        if let all = await server.settings(scope: "server") {
            page.serverSettings = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        }
        for account in page.accounts {
            if let all = await server.settings(scope: "account:\(account.id)") {
                page.settings[account.id] = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
            }
        }
        // ponytail: the newest 100 runs, filtered here — the runs list has no "fell back" filter.
        if let runs = await server.companyRuns(company: model.companyID, limit: 100) {
            page.fallbackRuns = runs.filter { $0.fallbackReason != nil }
            for run in page.fallbackRuns where model.issues[run.issueID ?? 0] == nil {
                if let issue = run.issueID { model.issues[issue] = await server.issue(issue) }
            }
        }
        if page.pickedAccount == nil { page.pickedAccount = page.visible(company: model.companyID).first?.id }
        let agent = page.chainAgent ?? model.liveRuns.first?.agentID ?? model.agents.keys.min()
        if let agent {
            page.chainAgent = agent
            await loadChain(agent, page: page, model: model, server: server)
        }
        page.isLoaded = true
    }

    private func loadChain(_ agent: Int64, page: AccountsPage, model: CompanyModel, server: CitadelServer) async {
        guard let info = model.agent(agent), let fallbacks = await server.fallbacks(agent: agent) else { return }
        guard page.chainAgent == agent else { return }
        page.chain = [FallbackEntry(harness: info.harness, model: info.model, isOwn: true)] + fallbacks
    }
}
