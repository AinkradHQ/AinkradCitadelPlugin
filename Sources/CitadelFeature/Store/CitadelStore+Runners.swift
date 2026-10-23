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

    /// "+ Add runner": registers it; the sheet then shows its key and start command once.
    func registerRunner(name: String, tags: [String]) {
        guard let server, let model else { return }
        let page = model.runnersPage
        page.registerFailure = nil
        Task {
            switch await server.registerRunner(name: name, tags: tags) {
            case .success(let registered):
                page.registered = registered
                await reloadRunners(model, server: server)
            case .failure(let answer):
                page.registerFailure = ActionFailure(
                    title: "Couldn't register \(name)", answer: answer, outcome: "No runner was added.")
            }
        }
    }

    /// Drain (it takes no new run; its runs finish) or put it back to work.
    func setDrained(_ runner: RunnerInfo, _ drained: Bool) {
        runnerChange(runner, drained ? "Couldn't drain \(runner.name)" : "Couldn't undrain \(runner.name)",
            outcome: drained ? "It still takes work." : "It stays drained.") { await $0.drain(runner: runner.id, drained) }
    }

    /// "Keep awake while jobs queue": the Mac's Power Nap preference.
    func setPowerNap(_ runner: RunnerInfo, _ enabled: Bool) {
        runnerChange(runner, "Couldn't change \(runner.name)'s Power Nap", outcome: "Its preference is unchanged.") {
            await $0.setPowerNap(runner: runner.id, enabled)
        }
    }

    /// "Remove runner…" (after its confirm): its key stops working and the card goes.
    func removeRunner(_ runner: RunnerInfo) {
        guard let server, let model else { return }
        let page = model.runnersPage
        page.failures[runner.id] = nil
        Task {
            if let answer = await server.removeRunner(runner.id) {
                page.failures[runner.id] = ActionFailure(
                    title: "Couldn't remove \(runner.name)", answer: answer, outcome: "It stays registered.")
            } else {
                page.runners.removeAll { $0.id == runner.id }
                page.disk[runner.id] = nil
                await reloadRunners(model, server: server)
            }
        }
    }

    /// "Probe log" / "Show last log": the end of the runner's log, in a sheet.
    func showRunnerLog(_ runner: RunnerInfo) {
        guard let server, let page = model?.runnersPage else { return }
        page.failures[runner.id] = nil
        Task {
            switch await server.runnerLog(runner.id) {
            case .success(let lines): page.log = (runner.id, lines)
            case .failure(let answer):
                page.failures[runner.id] = ActionFailure(
                    title: "Couldn't read \(runner.name)'s log", answer: answer, outcome: "Nothing was read.")
            }
        }
    }

    /// An action answered with the runner: its card updates; a refusal shows on it.
    private func runnerChange(
        _ runner: RunnerInfo, _ title: String, outcome: String,
        _ send: @escaping (CitadelServer) async -> Result<RunnerInfo, ServerAnswer>
    ) {
        guard let server, let page = model?.runnersPage else { return }
        page.failures[runner.id] = nil
        Task {
            switch await send(server) {
            case .success(let info):
                if let index = page.runners.firstIndex(where: { $0.id == runner.id }) { page.runners[index] = info }
            case .failure(let answer):
                page.failures[runner.id] = ActionFailure(title: title, answer: answer, outcome: outcome)
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
