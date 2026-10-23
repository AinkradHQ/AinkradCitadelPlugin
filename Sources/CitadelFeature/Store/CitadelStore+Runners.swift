import Foundation

/// Screen 10: runners, their disk and their limits (`runner:<id>`, decision #57), pushed by runner events.
extension CitadelStore {
    /// The screen opened: read everything it shows.
    func loadRunnersPage() {
        guard let server, let model else { return }
        Task { await fillRunners(model, server: server) }
    }

    /// Reads the runners and their disk again after a runner event; the sidebar's "3/4" always, the page once open.
    func reloadRunners(_ model: CompanyModel, server: CitadelServer) async {
        if model.runnersPage.isLoaded {
            await fillRunners(model, server: server)
        } else if let runners = await server.runnerList() {
            apply(runners, to: model)
        }
    }

    /// Sets a runner limit typed on its card; refused input never reaches the server (the field stays red).
    func setRunnerLimit(_ runner: Int64, key: String, text: String) {
        guard let server, let page = model?.runnersPage, let setting = page.settings[runner]?[key],
            let value = setting.parse(text), setting.accepts(text)
        else { return }
        Task {
            if let updated = await server.setSetting(scope: "runner:\(runner)", key: key, value: value) {
                page.settings[runner, default: [:]][key] = updated
            }
        }
    }

    /// "Wake now" (`now`) or "Run when I'm back" (`when_back`): the card shows the request until the runner
    /// connects; a refusal shows on the card (mockup 11 G).
    func wakeRunner(_ runner: Int64, when: String) {
        guard let server, let page = model?.runnersPage else { return }
        page.failures[runner] = nil
        Task {
            switch await server.wake(runner: runner, when: when) {
            case .success(let info):
                if let index = page.runners.firstIndex(where: { $0.id == runner }) { page.runners[index] = info }
            case .failure(let answer):
                let name = page.runners.first { $0.id == runner }?.name ?? "the runner"
                page.failures[runner] = ActionFailure(
                    title: "Couldn't wake \(name)", answer: answer, outcome: "Nothing was pushed.")
            }
        }
    }

    /// ↺: back to the server's value.
    func resetRunnerLimit(_ runner: Int64, key: String) {
        guard let server, let page = model?.runnersPage else { return }
        Task {
            if let updated = await server.resetSetting(scope: "runner:\(runner)", key: key) {
                page.settings[runner, default: [:]][key] = updated
            }
        }
    }

    private func fillRunners(_ model: CompanyModel, server: CitadelServer) async {
        let page = model.runnersPage
        guard let runners = await server.runnerList() else { return }
        apply(runners, to: model)
        if let all = await server.settings(scope: "server") {
            page.serverSettings = Dictionary(all.map { ($0.key, $0) }, uniquingKeysWith: { a, _ in a })
        }
        for runner in runners {
            if let disk = await server.runnerDisk(runner.id) { page.disk[runner.id] = disk }
            if let all = await server.settings(scope: "runner:\(runner.id)") {
                page.settings[runner.id] = Dictionary(
                    all.filter { RunnersPage.limitKeys.contains($0.key) }.map { ($0.key, $0) },
                    uniquingKeysWith: { a, _ in a })
            }
        }
        // The keys and repos the worktree lines name.
        let issues = Set(page.disk.values.flatMap { $0.worktrees.map(\.issueID) })
        for issue in issues {
            if model.issues[issue] == nil { model.issues[issue] = await server.issue(issue) }
            if model.issueRepos[issue] == nil { model.issueRepos[issue] = await server.issueRepos(issue) }
        }
        page.isLoaded = true
    }

    private func apply(_ runners: [RunnerInfo], to model: CompanyModel) {
        model.runnersPage.runners = runners.sorted { $0.name < $1.name }
        model.runners = Dictionary(uniqueKeysWithValues: runners.map { ($0.id, $0.name) })
        model.runnersOnline = runners.filter { $0.status == "online" }.count
    }
}
