import AinkradAppKit
import SwiftUI

/// Screens 03 Org, 04 Agent and the hire wizard: their extra reads and the agent actions, each confirmed by a
/// toast with the agent's figure (prototype `ui.js` toast) and Undo where the server can reverse it.
extension CitadelStore {
    /// The wizard's and the drawer's counts: accounts per harness, runners per tag, the company's skills.
    func loadOrgExtras() {
        guard let server, let model else { return }
        let page = model.orgPage
        Task {
            if let pool = await server.companyAccounts() { page.pool = pool }
            if let runners = await server.runnerList() { page.runners = runners }
            if let skills = await server.skills(company: model.companyID) { page.skillLibrary = skills }
        }
    }

    /// An opened agent's resolved skills and fallback chain.
    func loadAgentExtras(_ agent: Int64) {
        guard let server, let model else { return }
        let page = model.orgPage
        Task {
            if let skills = await server.agentSkills(agent) { page.agentSkills[agent] = skills }
            if let chain = await server.fallbacks(agent: agent) { page.chains[agent] = chain }
        }
        if page.pool.isEmpty { loadOrgExtras() }
    }

    /// The peek panel's week, success and recent runs: the agent's runs, once.
    func loadPeek(_ agent: Int64) {
        guard let server, let model else { return }
        if model.orgPage.agentSkills[agent] == nil {
            Task { if let skills = await server.agentSkills(agent) { model.orgPage.agentSkills[agent] = skills } }
        }
        guard model.agentRuns[agent] == nil else { return }
        Task {
            if let runs = await server.agentRuns(agent, limit: 50) { model.agentRuns[agent] = runs }
            for issue in Set((model.agentRuns[agent] ?? []).prefix(3).compactMap(\.issueID))
            where model.issues[issue] == nil {
                model.issues[issue] = await server.issue(issue)
            }
        }
    }

    /// Chat: the agent's newest thread, or the threads screen when it has none yet.
    func chat(with agent: Int64) {
        let thread = model?.threads().first { $0.key.agentID == agent }
        detail = nil
        screen = .threads
        if let thread {
            selectedThread = thread.key
            openThread(thread.key)
        }
    }

    func agentToast(
        _ agent: AgentInfo?, title: String, body: String? = nil, status: AinkradStatus = .success,
        undo: (@MainActor () -> Void)? = nil
    ) {
        let icon = agent.flatMap { agent in
            model.map { AnyView(AgentFigure(agent: agent, model: $0, size: 28)) }
        }
        toast(
            AinkradRichToast(
                title: title, body: body, status: status, icon: icon,
                actions: undo.map { [AinkradRichToastAction("Undo", run: $0)] } ?? []))
    }

    /// Pause (confirmed by the caller) parks the agent after its tool call; Undo resumes it.
    func pause(_ agent: AgentInfo) {
        perform("Couldn't pause \(agent.name)", outcome: "It keeps running.") {
            self.agentToast(
                agent, title: "\(agent.name) paused", body: "Wakes queue until you resume.", status: .warning
            ) {
                self.resume(agent)
            }
        } _: {
            await $0.pause(agent: agent.id)
        }
    }

    func resume(_ agent: AgentInfo) {
        perform("Couldn't resume \(agent.name)", outcome: "It stays paused.") {
            self.agentToast(agent, title: "\(agent.name) resumed", body: "Its queued wakes run now.")
        } _: {
            await $0.resume(agent: agent.id)
        }
    }

    /// Stop run now: the runner kills the harness; the worktree is kept.
    func stopRun(of agent: AgentInfo, run: Int64) {
        perform("Couldn't stop run #\(run)", outcome: "It keeps running.") {
            self.agentToast(
                agent, title: "Run #\(run) stopped", body: "Its issue is back in the queue.", status: .warning)
        } _: {
            await $0.stop(run: run)
        }
    }

    /// A new palette for the agent's figure everywhere; Undo puts the old one back.
    func setPalette(_ agent: AgentInfo, _ palette: String) {
        let old = agent.paletteID
        guard old != palette else { return }
        model?.agents[agent.id]?.paletteID = palette
        perform("Couldn't recolour \(agent.name)", outcome: "Its colour is unchanged.") {
            self.agentToast(
                agent, title: "Appearance updated", body: AinkradFigurePalette.named(palette)?.name ?? palette
            ) {
                self.setPalette(agent, old)
            }
        } _: { server in
            let refused = await server.setPalette(agent: agent.id, palette)
            if refused != nil { await MainActor.run { self.model?.agents[agent.id]?.paletteID = old } }
            return refused
        }
    }

    /// The agent's month budget, in tokens (`cap`) or dollars (`usdCap`, millionths, API minor 18): changed when it
    /// has one, created when it doesn't.
    func setMonthBudget(_ agent: AgentInfo, cap: Int64, usdCap: Int64? = nil, warnPercent: Int?) {
        guard let model else { return }
        let old = model.monthBudget(of: agent.id)
        let usd = serverSupports(minor: Self.trancheBMinor) ? usdCap : nil
        let now = usd.map { Fmt.budgetDollars(micros: $0) } ?? "\(Fmt.tokens(cap)) tok"
        let done: @MainActor @Sendable () -> Void = {
            self.agentToast(
                agent, title: "Budget \(old.map { $0.capWord } ?? "none") → \(now)",
                body: "Audited · applies to the next run.")
        }
        if let old {
            perform("Couldn't change \(agent.name)'s budget", outcome: "The budget is unchanged.", done: done) {
                await $0.setBudget(company: model.companyID, old, cap: cap, usdCap: usd, warnPercent: warnPercent)
            }
        } else {
            perform("Couldn't add \(agent.name)'s budget", outcome: "No budget was added.", done: done) {
                await $0.createBudget(
                    company: model.companyID, scope: "agent:\(agent.id)", period: "month", cap: cap, usdCap: usd,
                    warnPercent: warnPercent)
            }
        }
    }

    /// Reassign its work: each issue that is not in progress moves to `target` (live runs finish first).
    func reassign(_ issues: [IssueInfo], to target: AgentInfo) {
        let movable = issues.filter { $0.state != "in_progress" }
        perform("Couldn't move \(target.name)'s new work", outcome: "Some issues stayed where they were.") {
            self.agentToast(
                target, title: "Work moved to \(target.name)",
                body: "\(Wording.count(movable.count, "issue")) · \(target.name) is woken with the context.")
        } _: { server in
            for issue in movable {
                if let refused = await server.reassignIssue(issue.id, to: target.id) { return refused }
            }
            return nil
        }
    }

    /// Approve or reject a hire from the org (peek panel, pending hires, agent dock).
    func decideHire(_ approval: ApprovalInfo, approve: Bool, reply: String? = nil) {
        let agent = model?.agent(approval.agentID)
        decide(approval, approve: approve, reply: reply)
        agentToast(
            agent, title: approve ? "\(agent?.name ?? "Hire") approved" : "\(agent?.name ?? "Hire") rejected",
            body: approve ? "Seated — it picks up work from its team's queue." : "The proposer is told why.",
            status: approve ? .success : .warning)
    }

    /// The wizard's Propose hire: the proposal, then its palette once the pending agent exists; opens Approvals.
    func proposeHire(_ draft: AgentDraft, palette: String, done: @escaping @MainActor () -> Void) {
        guard draft.problem == nil, let server, let model else { return }
        Task {
            switch await server.proposeAgent(company: model.companyID, draft) {
            case .success(let proposed):
                let approvalID = proposed.approvalID
                actionFailure = nil
                done()
                if let preset = draft.chainPresetID, chainPresetsOn {
                    _ = await server.setAgentChain(agent: proposed.agentID, preset: preset)
                }
                if draft.paletteID == nil {
                    let pending = await server.approvals(company: model.companyID)
                    if let agent = pending?.first(where: { $0.id == approvalID })?.agentID {
                        _ = await server.setPalette(agent: agent, palette)
                    }
                }
                schedule([.org, .approvals])
                selectedApproval = approvalID
                toast(
                    AinkradRichToast(
                        title: "\(draft.name) proposed", body: "Waiting in Approvals — approve to seat it.",
                        status: .success, onOpen: { self.screen = .approvals }))
                screen = .approvals
                detail = nil
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: "Couldn't propose \(draft.name)", answer: answer, outcome: "Nobody was proposed.")
            }
        }
    }
}
