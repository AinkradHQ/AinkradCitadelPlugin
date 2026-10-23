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

    // ponytail: one list request per project, runner and account, then a history request per set value; fine
    // for tens of scopes — a server-side "list overridden" call would make it one.
    private func reloadLimits(_ model: CompanyModel, server: CitadelServer) async {
        let page = model.limitsPage
        let companyScope = "company:\(model.companyID)"
        if let all = await server.settings(scope: "server") { page.server = all }
        if let company = await server.settings(scope: companyScope) { page.company = company }
        var scopes: [(scope: String, owner: String)] = model.projects.map { ("project:\($0.id)", $0.key) }
        scopes += model.runners.sorted { $0.key < $1.key }.map { ("runner:\($0.key)", $0.value) }
        scopes += model.accounts.values.sorted { $0.id < $1.id }.map { ("account:\($0.id)", $0.label) }
        var below: [String: [LimitOverride]] = [:]
        for (scope, owner) in scopes {
            for setting in await server.settings(scope: scope) ?? [] where setting.isSet(at: scope) {
                below[setting.key, default: []].append(LimitOverride(scope: scope, owner: owner, value: setting.text))
            }
        }
        page.below = below
        var changes: [SettingChangeInfo] = []
        let setHere = page.company.filter { $0.isSet(at: companyScope) }.map { (companyScope, $0.key) }
        let setBelow = below.flatMap { key, overrides in overrides.map { ($0.scope, key) } }
        for (scope, key) in setHere + setBelow {
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
