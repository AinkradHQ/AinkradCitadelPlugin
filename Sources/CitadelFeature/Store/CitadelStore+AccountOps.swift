import AinkradAppKit
import Foundation

/// Accounts (prototype `accounts-panels.js`): pause / resume, the company's fallback triggers and at-limit choice,
/// the Limits drawer's warn and drop values, shared chains, the runners' logins — each with its toast and Undo where
/// the server can reverse it.
extension CitadelStore {
    /// The reads beyond the pool: runners (their logins), the company's trigger values and every agent's chain.
    func fillAccountExtras(_ model: CompanyModel, server: CitadelServer) async {
        let page = model.accountsPage
        if let runners = await server.runnerList() { page.runners = runners }
        if let all = await server.settings(scope: "company:\(model.companyID)") {
            page.companySettings = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        }
        for agent in model.agents.keys.sorted() {
            if let fallbacks = await server.fallbacks(agent: agent) { page.agentFallbacks[agent] = fallbacks }
        }
    }

    /// Toasts each window that passed its warn mark since the last read (the prototype's live warn toast).
    func toastWarnCrossings(old: [PoolAccount], page: AccountsPage) {
        guard !old.isEmpty else { return }
        for crossing in WarnCrossing.between(old: old, new: page.accounts, warnPercent: page.warnPercent) {
            toast(
                AinkradRichToast(
                    title: "\(crossing.account) passed \(crossing.percent)% of its \(crossing.window) window",
                    body: (crossing.reset.map { "Resets \($0.replacingOccurrences(of: "↺ ", with: "")) · " } ?? "")
                        + "new runs prefer other accounts", status: .warning))
        }
    }

    /// Pause (nothing new starts on it; running work finishes) or Resume, with Undo.
    func setAccountPaused(_ account: PoolAccount, _ paused: Bool, undoable: Bool = true) {
        guard let server, let page = model?.accountsPage else { return }
        Task {
            switch await server.setAccountStatus(
                account.id, paused: paused, reason: paused ? "paused from the app" : nil)
            {
            case .success(let saved):
                if let index = page.accounts.firstIndex(where: { $0.id == account.id }) {
                    page.accounts[index].status = saved.status
                    page.accounts[index].statusReason = saved.statusReason
                }
                let undo = AinkradRichToastAction("Undo") { [weak self] in
                    self?.setAccountPaused(account, !paused, undoable: false)
                }
                toast(
                    AinkradRichToast(
                        title: "\(account.label) \(paused ? "paused" : "resumed")",
                        body: paused ? "Running work finishes; nothing new starts on it." : nil,
                        status: paused ? .warning : .success, actions: undoable ? [undo] : []))
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: "Couldn't \(paused ? "pause" : "resume") \(account.label)", answer: answer,
                    outcome: "Its status is unchanged.")
            }
        }
    }

    /// A "Fall back when" chip: the company's `fallback.on_*` value, with Undo.
    func setFallbackTrigger(_ key: String, title: String, on: Bool, undoable: Bool = true) {
        guard let server, let model else { return }
        let page = model.accountsPage
        let scope = "company:\(model.companyID)"
        Task {
            guard let saved = await server.setSetting(scope: scope, key: key, value: on ? 1 : 0) else {
                toast(
                    AinkradRichToast(
                        title: "Couldn't change “\(title)”", body: "The server refused it.", status: .danger))
                return
            }
            page.companySettings[key] = saved
            let undo = AinkradRichToastAction("Undo") { [weak self] in
                self?.setFallbackTrigger(key, title: title, on: !on, undoable: false)
            }
            toast(
                AinkradRichToast(
                    title: on ? "Falls back when \(title)" : "No fallback when \(title)",
                    body: on ? "The run moves to the next chain entry · company setting" : "The run fails instead",
                    status: .success, actions: undoable ? [undo] : []))
        }
    }

    /// "At the limit": `account.at_limit` at the company (0 next chain entry, 1 queue) — per account needs the server.
    func setAtLimit(_ value: Int64) {
        guard let server, let model else { return }
        let page = model.accountsPage
        Task {
            if let saved = await server.setSetting(
                scope: "company:\(model.companyID)", key: "account.at_limit", value: value)
            {
                page.companySettings[saved.key] = saved
                toast(
                    AinkradRichToast(
                        title: "At limit → \(value == 1 ? "queue until reset" : "fall back to next entry")",
                        body: "Company setting · audited", status: .success))
            }
        }
    }

    /// The warn slider's release: the account's warn %, with Undo back to what it was.
    func setAccountWarn(_ account: PoolAccount, percent: Int, was: Int) {
        guard percent != was else { return }
        setAccountSetting(account.id, key: "account.warn_percent", text: "\(percent)")
        toast(
            AinkradRichToast(
                title: "\(account.label) warns at \(percent)%", body: "Pool-wide · audited", status: .success,
                actions: [
                    AinkradRichToastAction("Undo") { [weak self] in
                        self?.setAccountSetting(account.id, key: "account.warn_percent", text: "\(was)")
                    }
                ]))
    }

    /// I've logged in — recheck: the runners' logins read again (a probe endpoint would make it immediate).
    func recheckLogins(_ account: PoolAccount) {
        guard let server, let page = model?.accountsPage else { return }
        Task {
            if let runners = await server.runnerList() { page.runners = runners }
            let out = page.loggedOutRunners(account)
            toast(
                out.isEmpty
                    ? AinkradRichToast(
                        title: "\(account.label) logged in on every runner", body: "Runners shows the same.",
                        status: .success)
                    : AinkradRichToast(
                        title: "Still logged out on \(out.map(\.name).joined(separator: ", "))",
                        body: "Runners report their logins on their next probe.", status: .warning))
        }
    }

    /// Edits a shared chain: every agent on it gets the new fallbacks (their own entries are identical).
    func saveSharedChain(_ chain: SharedChain, fallbacks: [FallbackEntry]) {
        guard let server, let page = model?.accountsPage else { return }
        Task {
            for agent in chain.agents {
                if let stored = await server.setFallbacks(agent: agent, fallbacks) {
                    page.agentFallbacks[agent] = stored
                    if page.chainAgent == agent { page.chain = page.chain.filter(\.isOwn) + stored }
                }
            }
            toast(
                AinkradRichToast(
                    title: "\(chain.name) saved", body: "\(Wording.count(chain.agents.count, "agent")) use it",
                    status: .success))
        }
    }

    /// The picked agent's chain after an edit on the Agents tab: kept in the shared-chains map too.
    func noteChainSaved(agent: Int64, _ entries: [FallbackEntry]) {
        model?.accountsPage.agentFallbacks[agent] = entries.filter { !$0.isOwn }
    }
}
