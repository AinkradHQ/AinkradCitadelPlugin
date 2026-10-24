import CitadelClient
import Foundation

/// Screen 14: loading the projects and the selected one's profile, and the changes it sends.
extension CitadelStore {
    /// On open: every project's repos and sprint (the list), then the selected project's profile.
    func loadProjectsPage() {
        guard let server, let model else { return }
        let page = model.projectsPage
        Task {
            for project in model.projects {
                if let repos = await server.repos(project: project.id) { page.repos[project.id] = repos }
                page.sprintNames[project.id] = await server.activeSprintName(project: project.id)
            }
            page.companySettings = await server.settings(scope: "company:\(model.companyID)") ?? page.companySettings
            if let id = page.selected ?? model.projects.first?.id {
                await loadProfile(id, model: model, server: server)
            }
            page.isLoaded = true
        }
    }

    func selectProject(_ id: Int64) {
        guard let model else { return }
        model.projectsPage.selected = id
        model.projectsPage.problem = nil
        guard let server else { return }
        Task { await loadProfile(id, model: model, server: server) }
    }

    /// Reads a project's profile and repos again after a project event.
    func reloadProfile(_ project: Int64, model: CompanyModel, server: CitadelServer) async {
        guard model.projectsPage.profiles[project] != nil || model.projectsPage.repos[project] != nil else { return }
        await loadProfile(project, model: model, server: server)
    }

    private func loadProfile(_ project: Int64, model: CompanyModel, server: CitadelServer) async {
        let page = model.projectsPage
        async let profile = server.profile(project: project)
        async let repos = server.repos(project: project)
        async let settings = server.settings(scope: "project:\(project)")
        async let policy = server.policy(project: project)
        if let profile = await profile { page.profiles[project] = profile }
        if let policy = await policy { page.policies[project] = policy }
        if let repos = await repos { page.repos[project] = repos }
        if let settings = await settings { page.settings[project] = settings }
        await reloadKnowledge(project, model: model, server: server)
        // The "issues declare their repos" example: an issue in flight, preferring one that spans repos.
        guard let issues = await server.activeIssues(project: project) else { return }
        var first: (IssueInfo, [String])?
        for issue in issues.prefix(8) {
            guard let names = await server.issueRepos(issue.id), !names.isEmpty else { continue }
            if names.count > 1 {
                page.declared[project] = (issue, names)
                return
            }
            first = first ?? (issue, names)
        }
        page.declared[project] = first
    }

    // MARK: - Repos

    /// Drag-to-reorder: the new order goes to the server by name (decision #54, the PR merge order); a refusal
    /// puts the server's order back.
    func reorderRepos(project: Int64, _ repos: [RepoInfo]) {
        guard let server, let model else { return }
        let page = model.projectsPage
        let before = page.repos[project]
        page.repos[project] = repos
        Task {
            switch await server.orderRepos(project: project, names: repos.map(\.name)) {
            case .success(let saved): page.repos[project] = saved
            case .failure(let refusal):
                page.repos[project] = before
                page.problem = refusal
            }
        }
    }

    func makePrimary(_ repo: RepoInfo) {
        repoChange(project: repo.id) { await $0.setPrimary(repo: repo.id) }
    }

    func removeRepo(_ repo: RepoInfo) {
        repoChange(project: repo.id) { await $0.removeRepo(repo.id) }
    }

    func addRepo(project: Int64, name: String, url: String, branch: String, forge: String, tokenFile: String) {
        guard let server, let model else { return }
        let page = model.projectsPage
        let forgeConfig =
            tokenFile.isEmpty ? nil : Schemas.RepoForge(kind: forge, repo: name, tokenFile: tokenFile)
        let body = Schemas.RepoBody(
            defaultBranch: branch.isEmpty ? nil : branch, forge: forgeConfig, name: name, url: url)
        Task {
            switch await server.addRepo(project: project, body) {
            case .success(let repo): page.repos[project, default: []].append(repo)
            case .failure(let refusal): page.problem = refusal
            }
        }
    }

    /// A repo action that answers with the project's repos; `project` is found from the repo.
    private func repoChange(
        project repo: Int64, _ call: @escaping (CitadelServer) async -> Result<[RepoInfo], ServerAnswer>
    ) {
        guard let server, let model else { return }
        let page = model.projectsPage
        guard let project = page.repos.first(where: { $0.value.contains { $0.id == repo } })?.key else { return }
        Task {
            switch await call(server) {
            case .success(let repos):
                page.repos[project] = repos
                page.problem = nil
            case .failure(let refusal): page.problem = refusal
            }
        }
    }

    // MARK: - Profile

    /// One field at a time; the event the change raises reloads the rest.
    func updateProfile(project: Int64, _ patch: Schemas.ProfilePatch) {
        guard let server, let model else { return }
        Task {
            if let profile = await server.updateProfile(project: project, patch) {
                model.projectsPage.profiles[project] = profile
            }
        }
    }

    /// The policy's allowlist changed (an entry added or removed): the whole policy goes back, its mode kept.
    func setAllowlist(project: Int64, _ allow: [String]) {
        guard let server, let page = model?.projectsPage, var policy = page.policies[project] else { return }
        policy.allow = allow
        Task {
            switch await server.setPolicy(project: project, policy) {
            case .success(let saved): page.policies[project] = saved
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: "Couldn't change the allowlist", answer: answer, outcome: "The policy is unchanged.")
            }
        }
    }

    /// Accept applies an agent's proposal, Reject drops it with an optional reason; the profile comes back without
    /// it. A refusal is the 11 G banner.
    func decide(_ proposal: ProposalInfo, project: Int64, accept: Bool, reason: String? = nil) {
        guard let server, let model else { return }
        let reason = (reason?.trimmingCharacters(in: .whitespacesAndNewlines)).nonEmpty
        Task {
            switch await server.decide(proposal: proposal.id, project: project, accept: accept, reason: reason) {
            case .success(let profile):
                model.projectsPage.profiles[project] = profile
                if model.projectsPage.history[project] != nil { loadProfileHistory(project) }
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: "Couldn't \(accept ? "accept" : "reject") \(proposal.title)", answer: answer,
                    outcome: "The profile is unchanged.")
            }
        }
    }

    /// "History →": the profile's changes and proposals, newest first.
    func loadProfileHistory(_ project: Int64) {
        guard let server, let model else { return }
        Task {
            if let history = await server.profileHistory(project: project) {
                model.projectsPage.history[project] = history
            }
        }
    }

    /// "＋ New project": the new project joins the list, selected; a refusal (a taken key) stays in the sheet.
    func createProject(
        name: String, key: String, mode: String, done: @escaping @MainActor (ActionFailure?) -> Void
    ) {
        guard let server, let model else { return }
        let name = name.trimmingCharacters(in: .whitespaces)
        let key = key.trimmingCharacters(in: .whitespaces).uppercased()
        Task {
            switch await server.createProject(company: model.companyID, name: name, key: key, mode: mode) {
            case .success(let project):
                model.projects.append(project)
                done(nil)
                selectProject(project.id)
            case .failure(let answer):
                done(ActionFailure(title: "Couldn't create \(key)", answer: answer, outcome: "No project was made."))
            }
        }
    }

    // MARK: - Limits

    /// Sets a scoped setting from its typed text (already checked against the bounds); the screen's value updates
    /// from the answer.
    func setLimit(_ setting: ScopedSetting, scope: String, text: String) {
        guard let value = setting.parse(text), let server, let model else { return }
        Task {
            guard let saved = await server.setSetting(scope: scope, key: setting.key, value: value) else { return }
            model.storeSetting(saved, scope: scope)
        }
    }

    /// ↺: back to the inherited value.
    func resetLimit(_ setting: ScopedSetting, scope: String) {
        guard let server, let model else { return }
        Task {
            guard let saved = await server.resetSetting(scope: scope, key: setting.key) else { return }
            model.storeSetting(saved, scope: scope)
        }
    }
}

extension CompanyModel {
    /// Puts a setting the server answered with into every page that shows it at `scope`.
    func storeSetting(_ setting: ScopedSetting, scope: String) {
        func replace(_ list: inout [ScopedSetting]) {
            if let index = list.firstIndex(where: { $0.key == setting.key }) { list[index] = setting }
        }
        let parts = scope.split(separator: ":")
        if parts.first == "project", parts.count == 2, let id = Int64(parts[1]) {
            replace(&projectsPage.settings[id, default: []])
        } else if parts.first == "company" {
            replace(&projectsPage.companySettings)
            replace(&limitsPage.company)
        }
    }
}
