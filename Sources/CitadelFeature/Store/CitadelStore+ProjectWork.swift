import AinkradAppKit
import CitadelClient
import Foundation

/// The project page (prototype `projects.js` → `quest-*.js`): opening a project, its work, and every write the
/// Board, Backlog, Sprints and item drawer make. Each write updates the page at once and is put back when the
/// server refuses; a reversible one offers Undo.
extension CitadelStore {
    /// A card or the list opens the project page on Overview.
    func openProject(_ id: Int64) {
        guard let model else { return }
        let page = model.projectsPage
        page.openProject = id
        page.tab = .overview
        page.drawer = nil
        page.filter = WorkFilter()
        selectProject(id)
        loadWork(id)
    }

    func closeProject() { model?.projectsPage.openProject = nil }

    func loadWork(_ project: Int64) {
        guard let server, let model else { return }
        Task { await reloadWork(project, model: model, server: server) }
    }

    /// Reads a project's work again (after a write, or an issue / sprint event on it).
    func reloadWork(_ project: Int64, model: CompanyModel, server: CitadelServer) async {
        guard var work = await server.projectWork(project: project) else { return }
        let month = Calendar.current.dateInterval(of: .month, for: Date())?.start
        if let costs = await server.taskCosts(company: model.companyID, since: month) {
            let ids = Set(work.items.map(\.id))
            let mine = costs.filter { ids.contains($0.issueID) }
            work.monthSpend = mine.isEmpty ? nil : mine.reduce(0) { $0 + $1.costMicros }
        }
        model.projectsPage.work[project] = work
    }

    /// The project's QA agent: the reviewer a card dragged to In review is submitted to.
    func reviewer(of project: ProjectInfo) -> Int64? {
        guard let model else { return nil }
        let seats = model.departments.flatMap(\.teams).first { $0.id == project.teamID }?.seats ?? []
        return seats.map(\.agentID).first { model.agents[$0]?.role.lowercased() == "qa" }
    }

    // MARK: - Board

    /// A card dropped on a column: WIP first, then the state machine's step; Undo takes the reverse step.
    func moveItem(_ item: WorkItem, to column: String, project: ProjectInfo, undoing: Bool = false) {
        guard let model, let server, item.column != column else { return }
        let page = model.projectsPage
        let work = page.work[project.id] ?? ProjectWork()
        if let full = ProjectLogic.wipRefusal(moving: item, into: column, items: work.items, limits: work.wip) {
            return toast(AinkradRichToast(title: "Can't move \(item.key)", body: full, status: .warning))
        }
        let step: BoardStep
        switch ProjectLogic.step(for: item, to: column, reviewer: reviewer(of: project)) {
        case .success(let found): step = found
        case .failure(let why):
            return toast(AinkradRichToast(title: "Can't move \(item.key)", body: why.message, status: .warning))
        }
        let target = column == "todo" && item.state == "backlog" ? "todo" : column
        update(item.id, in: project.id) { $0.state = target }
        Task {
            if let refused = await server.transition(issue: item.id, step) {
                update(item.id, in: project.id) { $0.state = item.state }
                toast(AinkradRichToast(title: "Couldn't move \(item.key)", body: refused.message, status: .danger))
            } else if !undoing {
                let agent = item.ownerAgentID.flatMap { model.agents[$0]?.name }
                var moved = item
                moved.state = target
                toast(
                    AinkradRichToast(
                        title: "\(item.key) → \(ProjectLogic.title(column))",
                        body: agent.map { "\($0) is told on the issue." }, status: .success,
                        actions: [
                            AinkradRichToastAction("Undo") { [weak self] in
                                self?.moveItem(moved, to: item.column, project: project, undoing: true)
                            }
                        ]))
            }
            await reloadWork(project.id, model: model, server: server)
        }
    }

    /// "＋ Add item" / dock New item: the new issue opens in the drawer.
    func newItem(project: Int64) {
        guard let model, let server else { return }
        let page = model.projectsPage
        let kind = page.filter.kind ?? "task"
        Task {
            switch await server.createIssue(project: project, title: "New item", kind: kind, epic: page.filter.epic) {
            case .success(let item):
                page.work[project, default: ProjectWork()].items.append(item)
                openItem(item.id)
            case .failure(let answer):
                toast(AinkradRichToast(title: "Couldn't add an item", body: answer.message, status: .danger))
            }
        }
    }

    // MARK: - Backlog and sprints

    /// A row dropped on a sprint section (`nil` = the backlog).
    func setSprint(_ item: WorkItem, to sprint: SprintDetail?, project: Int64, undoing: Bool = false) {
        guard let model, let server, item.sprintID != sprint?.id else { return }
        update(item.id, in: project) { $0.sprintID = sprint?.id }
        Task {
            let refused =
                sprint == nil
                ? await server.setSprint(issue: item.id, sprint: nil)
                : await server.setSprint(issue: item.id, sprint: sprint?.id)
            if let refused {
                update(item.id, in: project) { $0.sprintID = item.sprintID }
                toast(AinkradRichToast(title: "Couldn't move \(item.key)", body: refused.message, status: .danger))
            } else if !undoing {
                let before = model.projectsPage.work[project]?.sprints.first { $0.id == item.sprintID }
                var moved = item
                moved.sprintID = sprint?.id
                toast(
                    AinkradRichToast(
                        title: sprint.map { "\(item.key) added to \($0.name)" } ?? "\(item.key) moved to the backlog",
                        status: .success,
                        actions: [
                            AinkradRichToastAction("Undo") { [weak self] in
                                self?.setSprint(moved, to: before, project: project, undoing: true)
                            }
                        ]))
            }
            await reloadWork(project, model: model, server: server)
        }
    }

    /// The grip: a new place in the backlog's rank.
    func rank(_ item: WorkItem, _ place: RankPlace, project: Int64) {
        guard let model, let server else { return }
        Task {
            if let refused = await server.move(issue: item.id, place) {
                toast(AinkradRichToast(title: "Couldn't reorder \(item.key)", body: refused.message, status: .danger))
            }
            await reloadWork(project, model: model, server: server)
        }
    }

    /// "Start S5": the active sprint closes, its unfinished items carry over, and the next one is committed.
    func startNextSprint(project: Int64) {
        guard let model, let server, let work = model.projectsPage.work[project], let next = work.next else { return }
        Task {
            if let active = work.active, let refused = await server.closeSprint(active.id, carryTo: next.id) {
                return toast(
                    AinkradRichToast(title: "Couldn't close \(active.name)", body: refused.message, status: .danger))
            }
            if let refused = await server.commitSprint(next.id) {
                toast(AinkradRichToast(title: "Couldn't start \(next.name)", body: refused.message, status: .danger))
            } else {
                toast(AinkradRichToast(title: "Sprint \(next.name) started", body: next.goal, status: .success))
            }
            await reloadWork(project, model: model, server: server)
        }
    }

    /// "Plan S5" with nothing planned yet: a two-week sprint right after the active one.
    func planNextSprint(project: Int64) {
        guard let model, let server else { return }
        let work = model.projectsPage.work[project] ?? ProjectWork()
        let start = (work.active?.endsOn ?? Date()).addingTimeInterval(3 * 86_400)
        let name = Self.nextSprintName(after: work.sprints.last?.name)
        Task {
            if let refused = await server.planSprint(
                project: project, name: name, goal: "", start: start, end: start.addingTimeInterval(11 * 86_400))
            {
                toast(AinkradRichToast(title: "Couldn't plan \(name)", body: refused.message, status: .danger))
            } else {
                toast(
                    AinkradRichToast(
                        title: "Sprint \(name) planned", body: "Drag items into it on the Backlog.", status: .success))
                model.projectsPage.tab = .backlog
            }
            await reloadWork(project, model: model, server: server)
        }
    }

    /// `S4` → `S5`, `L2` → `L3`; `S1` with none.
    static func nextSprintName(after name: String?) -> String {
        guard let name, let digits = name.firstIndex(where: \.isNumber), let number = Int(name[digits...]) else {
            return "S1"
        }
        return "\(name[..<digits])\(number + 1)"
    }

    // MARK: - Item drawer

    func openItem(_ id: Int64) {
        guard let model, let server else { return }
        model.projectsPage.drawer = .item(id)
        Task {
            if let runs = await server.issueRuns(company: model.companyID, issue: id) {
                model.projectsPage.itemRuns[id] = runs
            }
            if let activity = await server.issueActivity(id) { model.projectsPage.itemActivity[id] = activity }
        }
    }

    func assign(_ item: WorkItem, to agent: Int64, project: Int64) {
        write(
            item, project: project, title: "\(item.key) · assignee updated",
            body: model?.agents[agent].map { "\($0.name) is woken with the issue." }
        ) {
            $0.ownerAgentID = agent
        } call: {
            await $0.reassignIssue(item.id, to: agent)
        }
    }

    func estimate(_ item: WorkItem, points: Int, project: Int64) {
        write(item, project: project, title: "\(item.key) · estimate updated") {
            $0.points = points
        } call: {
            await $0.estimate(issue: item.id, points: points)
        }
    }

    func setEpic(_ item: WorkItem, epic: Int64?, project: Int64) {
        write(item, project: project, title: "\(item.key) · epic updated") {
            $0.epicID = epic
        } call: {
            await $0.setEpic(issue: item.id, epic: epic)
        }
    }

    /// The server has one priority flag: High bumps it (and its wakes) to the top.
    func prioritize(_ item: WorkItem, project: Int64) {
        write(item, project: project, title: "\(item.key) · priority raised") {
            $0.priority = true
        } call: {
            await $0.bump(issue: item.id)
        }
    }

    /// Comment: wakes the agent it @mentions, else the issue's working agent.
    func comment(on item: WorkItem, _ text: String) {
        guard let server else { return }
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty else { return }
        Task {
            switch await server.post(issue: item.id, body: body, wake: nil) {
            case .success(let posted):
                let woke = posted.wokeAgentID.flatMap { model?.agents[$0]?.name }
                toast(AinkradRichToast(title: "Comment posted", body: woke.map { "\($0) is woken." }, status: .success))
                if let activity = await server.issueActivity(item.id) {
                    model?.projectsPage.itemActivity[item.id] = activity
                }
            case .failure(let answer):
                toast(AinkradRichToast(title: "Couldn't post the comment", body: answer.message, status: .danger))
            }
        }
    }

    // MARK: - Config

    /// A repo command edited in place; the field flashes when saved.
    func saveCommands(_ repo: RepoInfo, project: Int64, label: String, done: @escaping @MainActor (Bool) -> Void) {
        guard let server, let model else { return }
        Task {
            switch await server.updateRepo(repo) {
            case .success(let saved):
                if let index = model.projectsPage.repos[project]?.firstIndex(where: { $0.id == saved.id }) {
                    model.projectsPage.repos[project]?[index] = saved
                }
                toast(AinkradRichToast(title: "\(repo.name) · \(label.lowercased()) command saved", status: .success))
                done(true)
            case .failure(let answer):
                toast(AinkradRichToast(title: "Couldn't save \(repo.name)", body: answer.message, status: .danger))
                done(false)
            }
        }
    }

    /// Teams: the server keeps one owning team, so attaching another makes it the owner.
    func setTeam(_ team: TeamInfo, project: ProjectInfo) {
        guard let server, let model, project.teamID != team.id else { return }
        Task {
            if let refused = await server.setTeam(project: project.id, team: team.id) {
                return toast(
                    AinkradRichToast(title: "Couldn't change the team", body: refused.message, status: .danger))
            }
            if let index = model.projects.firstIndex(where: { $0.id == project.id }) {
                model.projects[index].teamID = team.id
            }
            toast(
                AinkradRichToast(
                    title: "\(team.name) owns \(project.key)", body: "Its lead plans sprints with the PO.",
                    status: .success))
        }
    }

    // MARK: - Helpers

    private func update(_ item: Int64, in project: Int64, _ change: (inout WorkItem) -> Void) {
        guard let page = model?.projectsPage, let index = page.work[project]?.items.firstIndex(where: { $0.id == item })
        else { return }
        change(&page.work[project, default: ProjectWork()].items[index])
    }

    /// A field write from the item drawer: shown at once, put back on a refusal.
    private func write(
        _ item: WorkItem, project: Int64, title: String, body: String? = nil,
        _ change: @escaping (inout WorkItem) -> Void,
        call: @escaping (CitadelServer) async -> ServerAnswer?
    ) {
        guard let server, let model else { return }
        update(item.id, in: project, change)
        Task {
            if let refused = await call(server) {
                update(item.id, in: project) { $0 = item }
                toast(AinkradRichToast(title: "Couldn't update \(item.key)", body: refused.message, status: .danger))
            } else {
                toast(AinkradRichToast(title: title, body: body, status: .success))
            }
            await reloadWork(project, model: model, server: server)
        }
    }
}
