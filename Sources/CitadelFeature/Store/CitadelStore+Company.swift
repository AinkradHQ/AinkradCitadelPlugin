import AppKit
import CitadelClient
import Foundation

/// An agent or a run opened from a screen; the sidebar keeps its screen selected underneath.
enum Detail: Hashable {
    case agent(Int64)
    case run(Int64)
}

/// The selected company's data: one load when its stream goes live, then targeted reads the events ask for.
extension CitadelStore {
    static let limitKeys = ["run.token_cap", "run.stall_after_secs", "budget.warn_percent", "breaker.loop_threshold"]

    func open(_ detail: Detail?) {
        self.detail = detail
        guard let detail, let model, let server else { return }
        Task {
            switch detail {
            case .agent(let id): await loadAgentPage(id, model: model, server: server)
            case .run(let id): await loadRunPage(id, model: model, server: server)
            }
        }
    }

    func loadCompany() {
        guard let server, let id = company?.id else { return }
        let model = CompanyModel(companyID: id)
        self.model = model
        Task { await load(model, server: server) }
    }

    /// Approve (or deny) from Home, the inbox, the agent page or the run's decision bar, with an optional reply to
    /// the agent that asked; the approval's event reloads the list.
    func decide(_ approval: ApprovalInfo, approve: Bool, raiseTokens: Int64? = nil, reply: String? = nil) {
        guard let server else { return }
        let reply = reply.flatMap { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : $0 }
        Task {
            if let answer = await server.decision(
                approval: approval.id, approve: approve, raiseTokens: raiseTokens, reply: reply)
            {
                let title = model?.summary(approval).title.replacingOccurrences(of: "Commit sprint", with: "sprint")
                actionFailure = ActionFailure(
                    title: "Couldn't \(approve ? "approve" : "deny") \(title ?? "it")", answer: answer,
                    outcome: approve ? "Nothing was approved." : "Nothing was denied.")
            } else {
                model?.answer(approval, approved: approve, reply: reply)
            }
        }
    }

    // MARK: - Loading

    private func load(_ model: CompanyModel, server: CitadelServer) async {
        let id = model.companyID
        async let org = server.orgChart(company: id)
        async let approvals = server.approvals(company: id)
        async let stuck = server.stuck()
        async let costs = server.costs(company: id)
        async let requirements = server.requirements()
        async let sprint = server.activeSprint(company: id)
        async let accounts = server.accounts(company: id)
        async let runners = server.runners()
        async let projects = server.projects(company: id)
        if let (agents, departments) = await org {
            model.agents = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
            model.departments = departments
        }
        model.approvals = await approvals ?? []
        await loadAnswered(model, server: server)
        await loadQuestions(model, server: server)
        model.stuck = await stuck ?? []
        model.requirements = await requirements ?? []
        model.sprint = await sprint
        model.accounts = Dictionary(uniqueKeysWithValues: (await accounts ?? []).map { ($0.id, $0) })
        if let (names, online) = await runners {
            model.runners = names
            model.runnersOnline = online
        }
        model.projects = await projects ?? []
        if let (spend, budgets) = await costs { apply(spend: spend, budgets: budgets, to: model) }
        await loadSpendToday(model, server: server)
        for key in Self.limitKeys {
            model.limits[key] = await server.setting(scope: "company:\(id)", key: key)
        }
        // The run each busy or waiting agent is on: the live-run cards and the org's "what it's on now".
        for agent in model.agents.values where agent.figure != .idle && agent.figure != .rest {
            await reload(.agentRun(agent.id), model: model, server: server)
        }
        // The keys of the issues approvals and stuck rows name.
        for issue in Set(model.approvals.compactMap(\.issueID) + model.stuck.compactMap(\.issueID)) {
            await reload(.issue(issue), model: model, server: server)
        }
        model.isLoaded = true
        for agent in model.agents.values where agent.avatarPath != nil {
            loadAvatar(agent.id, model: model, server: server)
        }
    }

    private func loadAgentPage(_ id: Int64, model: CompanyModel, server: CitadelServer) async {
        guard let runs = await server.agentRuns(id, limit: 50) else { return }
        model.agentRuns[id] = runs
        for run in runs.prefix(1) { model.runs[run.id] = model.runs[run.id] ?? run }
        for issue in Set(runs.compactMap(\.issueID)) where model.issues[issue] == nil {
            model.issues[issue] = await server.issue(issue)
        }
        if let current = runs.first, current.isLive, model.transcripts[current.id] == nil {
            model.transcripts[current.id] = await server.transcript(run: current.id)
        }
    }

    private func loadRunPage(_ id: Int64, model: CompanyModel, server: CitadelServer) async {
        if let run = await server.run(id) { model.runs[id] = run }
        if model.transcripts[id] == nil { model.transcripts[id] = await server.transcript(run: id) ?? [] }
        guard let issueID = model.runs[id]?.issueID else { return }
        if let costs = await server.issueCosts(company: model.companyID) {
            model.issueCosts = Dictionary(costs.map { ($0.issueID, $0) }, uniquingKeysWith: { a, _ in a })
        }
        if model.issues[issueID] == nil { model.issues[issueID] = await server.issue(issueID) }
        if model.issueRepos[issueID] == nil { model.issueRepos[issueID] = await server.issueRepos(issueID) }
        if let project = model.issues[issueID]?.projectID {
            for key in Self.limitKeys where model.limits["project:\(project)|\(key)"] == nil {
                model.limits["project:\(project)|\(key)"] = await server.setting(scope: "project:\(project)", key: key)
            }
        }
    }

    private func loadAvatar(_ agent: Int64, model: CompanyModel, server: CitadelServer) {
        Task {
            if let data = await server.avatar(agent: agent), let image = NSImage(data: data) {
                model.avatars[agent] = image
            }
        }
    }

    // MARK: - Reloads the events ask for

    /// Coalesces a burst of events into one round of reads, a quarter second later.
    func schedule(_ reloads: Set<Reload>) {
        guard !reloads.isEmpty else { return }
        pendingReloads.formUnion(reloads)
        guard reloadTask == nil, let model, let server else { return }
        reloadTask = Task {
            try? await Task.sleep(for: .milliseconds(250))
            let batch = pendingReloads
            pendingReloads = []
            reloadTask = nil
            for reload in batch { await self.reload(reload, model: model, server: server) }
        }
    }

    private func reload(_ reload: Reload, model: CompanyModel, server: CitadelServer) async {
        let id = model.companyID
        switch reload {
        case .org:
            if let (agents, departments) = await server.orgChart(company: id) {
                model.agents = Dictionary(uniqueKeysWithValues: agents.map { ($0.id, $0) })
                model.departments = departments
            }
        case .approvals:
            model.approvals = await server.approvals(company: id) ?? model.approvals
            await loadAnswered(model, server: server)
        case .questions: await loadQuestions(model, server: server)
        case .comments(let issue):
            if let comments = await server.comments(issue: issue) { model.comments[issue] = comments }
        case .issueFresh(let issue):
            if let info = await server.issue(issue) { model.issues[issue] = info }
        case .stuck:
            model.stuck = await server.stuck() ?? model.stuck
            for issue in model.stuck.compactMap(\.issueID) where model.issues[issue] == nil {
                model.issues[issue] = await server.issue(issue)
            }
        case .costs:
            if let (spend, budgets) = await server.costs(company: id) {
                apply(spend: spend, budgets: budgets, to: model)
            }
            await loadSpendToday(model, server: server)
            await refreshCostTasks(model, server: server)
        case .requirements: model.requirements = await server.requirements() ?? model.requirements
        case .sprint: model.sprint = await server.activeSprint(company: id)
        case .accounts:
            if let accounts = await server.accounts(company: id) {
                model.accounts = Dictionary(uniqueKeysWithValues: accounts.map { ($0.id, $0) })
            }
        case .agent(let agent):
            if let info = await server.agent(agent) { model.agents[agent] = info }
            await self.reload(.agentRun(agent), model: model, server: server)
        case .agentRun(let agent):
            if let run = await server.agentRuns(agent, limit: 1)?.first {
                model.runs[run.id] = run
                await self.reload(.issue(run.issueID ?? 0), model: model, server: server)
            }
        case .run(let run):
            guard let info = await server.run(run) else { return }
            model.runs[run] = info
            if let index = model.agentRuns[info.agentID]?.firstIndex(where: { $0.id == run }) {
                model.agentRuns[info.agentID]?[index] = info
            } else if model.agentRuns[info.agentID] != nil {
                model.agentRuns[info.agentID]?.insert(info, at: 0)
            }
            if let agent = await server.agent(info.agentID) {
                model.agents[info.agentID] = AgentInfo(agent, lastRunState: info.state)
            }
            if let issue = info.issueID, model.issues[issue] == nil { model.issues[issue] = await server.issue(issue) }
        case .issue(let issue):
            guard issue > 0, model.issues[issue] == nil else { return }
            model.issues[issue] = await server.issue(issue)
        case .thread(let requirement): await reloadThread(requirement, model: model, server: server)
        case .artifacts: await reloadArtifacts(model, server: server)
        case .profile(let project): await reloadProfile(project, model: model, server: server)
        case .settings: await reloadSettings(model, server: server)
        case .runners: await reloadRunners(model, server: server)
        }
    }

    /// Today's spend: the day's issues added up (an unpriced run counts as a run, never as $0).
    private func loadSpendToday(_ model: CompanyModel, server: CitadelServer) async {
        guard
            let costs = await server.issueCosts(
                company: model.companyID, since: Calendar.current.startOfDay(for: Date()))
        else { return }
        model.spendToday = IssueCost(
            issueID: 0, tokens: costs.map(\.tokens).reduce(0, +), costMicros: costs.map(\.costMicros).reduce(0, +),
            runs: costs.map(\.runs).reduce(0, +), unpricedRuns: costs.map(\.unpricedRuns).reduce(0, +))
    }

    private func apply(spend: SpendInfo, budgets: [Schemas.BudgetStanding], to model: CompanyModel) {
        model.spend = spend
        model.budgets = budgets.map { budget in
            BudgetInfo(budget) { scope in
                let parts = scope.split(separator: ":")
                let id = parts.count == 2 ? Int64(parts[1]) : nil
                switch parts.first {
                case "agent": return model.agent(id)?.name ?? "Agent"
                case "company": return company?.name ?? "Company"
                case "department": return model.departments.first { $0.id == id }?.name ?? "Department"
                case "sprint": return model.sprint?.id == id ? "Sprint \(model.sprint?.name ?? "")" : "Sprint"
                default: return "Project"
                }
            }
        }
    }
}

extension AgentInfo {
    /// The agent as the server sent it, with a hard error told from a stall by its last run (decision #63).
    init(_ agent: AgentInfo, lastRunState: String) {
        self = agent
        if figure == .confused { figure = AgentLook.figure("confused", lastRunState: lastRunState) }
    }
}
