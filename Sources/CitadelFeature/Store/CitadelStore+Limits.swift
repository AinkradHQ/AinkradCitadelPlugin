import Foundation

/// Screen 16: every setting at the server and this company, what is set below it, and the newest changes.
extension CitadelStore {
    func loadLimitsPage() {
        guard let server, let model else { return }
        Task {
            await reloadLimits(model, server: server)
            model.limitsPage.isLoaded = true
        }
    }

    /// Reads the scoped settings again after a setting event.
    func reloadSettings(_ model: CompanyModel, server: CitadelServer) async {
        if model.limitsPage.isLoaded { await reloadLimits(model, server: server) }
        for project in model.projectsPage.settings.keys {
            if let settings = await server.settings(scope: "project:\(project)") {
                model.projectsPage.settings[project] = settings
            }
        }
        if model.projectsPage.isLoaded, let company = await server.settings(scope: "company:\(model.companyID)") {
            model.projectsPage.companySettings = company
        }
    }

    /// The company's and its projects' values come from one call (`listOverriddenSettings`); runners and accounts
    /// are server-wide / pool-wide (#56, #57), outside it, so each is read at its scope. Recent changes read the
    /// history of the newest values only.
    private func reloadLimits(_ model: CompanyModel, server: CitadelServer) async {
        let page = model.limitsPage
        let companyScope = "company:\(model.companyID)"
        if let all = await server.settings(scope: "server") { page.server = all }
        if let company = await server.settings(scope: companyScope) { page.company = company }
        let overridden = await server.overriddenSettings(company: model.companyID) ?? []
        var below: [String: [LimitOverride]] = [:]
        for value in overridden where value.scope != companyScope {
            let owner = model.projects.first { "project:\($0.id)" == value.scope }?.key ?? value.scope
            below[value.key, default: []].append(
                LimitOverride(
                    scope: value.scope, owner: owner, value: ScopedSetting.format(value.value, unit: value.unit)))
        }
        var pooled: [(scope: String, owner: String)] = model.runners.sorted { $0.key < $1.key }.map {
            ("runner:\($0.key)", $0.value)
        }
        pooled += model.accounts.values.sorted { $0.id < $1.id }.map { ("account:\($0.id)", $0.label) }
        var pooledSet: [(scope: String, key: String)] = []
        for (scope, owner) in pooled {
            for setting in await server.settings(scope: scope) ?? [] where setting.isSet(at: scope) {
                below[setting.key, default: []].append(LimitOverride(scope: scope, owner: owner, value: setting.text))
                pooledSet.append((scope, setting.key))
            }
        }
        page.below = below
        let newest = overridden.sorted { $0.setAt > $1.setAt }.prefix(4).map { (scope: $0.scope, key: $0.key) }
        var changes: [SettingChangeInfo] = []
        for (scope, key) in newest + pooledSet {
            changes += await server.settingHistory(scope: scope, key: key) ?? []
        }
        page.changes = Array(changes.sorted { $0.seq > $1.seq }.prefix(4))
    }

    /// An override chip opens the screen that owns its scope.
    func openOverride(_ override: LimitOverride) {
        let parts = override.scope.split(separator: ":")
        guard parts.count == 2, let id = Int64(parts[1]) else { return }
        isShowingSettings = false
        detail = nil
        switch parts[0] {
        case "project":
            screen = .projects
            selectProject(id)
        case "runner": screen = .runners
        default: screen = .accounts
        }
    }
}
