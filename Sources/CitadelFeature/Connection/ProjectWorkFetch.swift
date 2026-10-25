import CitadelClient
import Foundation

/// The project page's work reads and writes (Board, Backlog, Sprints, Timeline, Reports, the item drawer): the
/// same endpoints AinkradQuest's server mode uses, through `CitadelClient`.
extension CitadelServer {
    /// Issues, epics, sprints, WIP limits, velocity, capacity and flow of one project; the active sprint's report.
    func projectWork(project: Int64) async -> ProjectWork? {
        async let issues = read("listProjectIssues") { () async throws -> [WorkItem]? in
            guard case .ok(let ok) = try await client.listProjectIssues(path: .init(id: project)) else { return nil }
            return try ok.body.json.map(WorkItem.init)
        }
        async let epics = read("listEpics") { () async throws -> [EpicInfo]? in
            guard case .ok(let ok) = try await client.listEpics(path: .init(id: project)) else { return nil }
            return try ok.body.json.map(EpicInfo.init)
        }
        async let sprints = read("listSprints") { () async throws -> [SprintDetail]? in
            guard case .ok(let ok) = try await client.listSprints(path: .init(id: project)) else { return nil }
            return try ok.body.json.map(SprintDetail.init).sorted { $0.id < $1.id }
        }
        async let wip = read("listWipLimits") { () async throws -> [String: Int]? in
            guard case .ok(let ok) = try await client.listWipLimits(path: .init(id: project)) else { return nil }
            return Dictionary(
                try ok.body.json.compactMap { w in w.limit.map { (w.state.word, Int($0)) } }, uniquingKeysWith: { $1 })
        }
        async let velocity = read("getVelocity") { () async throws -> Schemas.Velocity? in
            guard case .ok(let ok) = try await client.getVelocity(path: .init(id: project), query: .init(limit: 6))
            else { return nil }
            return try ok.body.json
        }
        async let capacity = read("getTeamCapacity") { () async throws -> [Int64: Int]? in
            guard case .ok(let ok) = try await client.getTeamCapacity(path: .init(id: project)) else { return nil }
            return Dictionary(
                try ok.body.json.members.compactMap { m in m.capacity.map { (m.agentId, Int($0)) } },
                uniquingKeysWith: { $1 })
        }
        guard let items = await issues else { return nil }
        var work = ProjectWork(items: items)
        work.epics = await epics ?? []
        work.sprints = await sprints ?? []
        work.wip = await wip ?? [:]
        work.capacity = await capacity ?? [:]
        if let velocity = await velocity {
            work.velocityAverage = velocity.average
            work.velocity = velocity.sprints.map {
                VelocityPoint(sprintID: $0.sprintId, committed: Int($0.committed), completed: Int($0.completed))
            }
        }
        if let active = work.active { work.report = await sprintReport(active.id) }
        (work.cycleDays, work.throughput) = await flow(project: project)
        return work
    }

    func sprintReport(_ sprint: Int64) async -> SprintReportInfo? {
        await read("getSprintReport") {
            guard case .ok(let ok) = try await client.getSprintReport(path: .init(id: sprint)) else { return nil }
            return SprintReportInfo(try ok.body.json)
        }
    }

    /// Cycle times of the last six weeks' finished items, and items done per week (one flow read per week).
    private func flow(project: Int64, now: Date = Date()) async -> ([Double], [(week: String, done: Int)]) {
        let calendar = Calendar(identifier: .iso8601)
        var cycles: [Double] = []
        var weeks: [(String, Int)] = []
        for back in (0..<6).reversed() {
            guard let end = calendar.date(byAdding: .weekOfYear, value: -back, to: now),
                let start = calendar.date(byAdding: .weekOfYear, value: -1, to: end)
            else { continue }
            let iso = Date.ISO8601FormatStyle()
            let flow: Schemas.ProjectFlow? = await read("getProjectFlow") {
                guard
                    case .ok(let ok) = try await client.getProjectFlow(
                        path: .init(id: project), query: .init(since: start.formatted(iso), until: end.formatted(iso)))
                else { return nil }
                return try ok.body.json
            }
            guard let flow else { continue }
            weeks.append(("W\(calendar.component(.weekOfYear, from: end))", flow.throughput))
            cycles += flow.issues.compactMap { $0.cycleSecs.map { Double($0) / 86_400 } }
        }
        return (cycles, weeks)
    }

    // MARK: - Writes

    func transition(issue: Int64, _ step: BoardStep) async -> ServerAnswer? {
        func actor(_ agent: Int64?) -> Schemas.Actor {
            agent.map { .agent(.init(agentId: $0, kind: .agent)) } ?? .human(.init(kind: .human, userId: 1))
        }
        func next(_ agent: Int64?) -> Schemas.NextActor {
            agent.map { .agent(.init(agentId: $0, kind: .agent)) } ?? .human(.init(kind: .human, userId: 1))
        }
        let body: Schemas.Transition =
            switch step {
            case .ready: .ready(.init(kind: .ready))
            case .start: .start(.init(kind: .start))
            case .done: .done(.init(kind: .done))
            case .approve: .approve(.init(kind: .approve))
            case .submitForReview(let reviewer):
                .submitForReview(.init(kind: .submitForReview, reviewer: actor(reviewer)))
            case .requestChanges(let assignee): .requestChanges(.init(assignee: actor(assignee), kind: .requestChanges))
            case .reopen(let agent): .reopen(.init(kind: .reopen, next: next(agent)))
            }
        return await act { try await client.transitionIssue(path: .init(id: issue), body: .json(body)) }
    }

    func move(issue: Int64, _ place: RankPlace) async -> ServerAnswer? {
        let body: Schemas.MoveBody =
            switch place {
            case .top: .init(to: .init(value1: .top))
            case .before(let anchor): .init(anchorIssueId: anchor, to: .init(value1: .before))
            case .after(let anchor): .init(anchorIssueId: anchor, to: .init(value1: .after))
            }
        return await act { try await client.moveIssue(path: .init(id: issue), body: .json(body)) }
    }

    func setEpic(issue: Int64, epic: Int64?) async -> ServerAnswer? {
        await act { try await client.setIssueEpic(path: .init(id: issue), body: .json(.init(epicId: epic))) }
    }

    func estimate(issue: Int64, points: Int?) async -> ServerAnswer? {
        await act {
            try await client.estimateIssue(
                path: .init(id: issue), body: .json(.init(points: points.map { Int32(clamping: $0) })))
        }
    }

    /// "＋ Add item": a new issue, in To do unless the server decides otherwise.
    func createIssue(project: Int64, title: String, kind: String, epic: Int64?) async -> Result<WorkItem, ServerAnswer>
    {
        let body = Schemas.NewIssueBody(
            epicId: epic, kind: .init(value1: .init(rawValue: kind), value2: kind), points: 2, title: title)
        return await attempt({ try await client.createIssue(path: .init(id: project), body: .json(body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return WorkItem(try ok.body.json)
        }
    }

    /// Closes the active sprint, carrying its unfinished items to `carryTo`.
    func closeSprint(_ sprint: Int64, carryTo: Int64?) async -> ServerAnswer? {
        await act { try await client.closeSprint(path: .init(id: sprint), body: .json(.init(carryTo: carryTo))) }
    }

    /// The owner's commit: the sprint starts (or waits on a sprint_commit approval under the PO policy).
    func commitSprint(_ sprint: Int64) async -> ServerAnswer? {
        await act { try await client.commitSprint(path: .init(id: sprint), body: .json(.init())) }
    }

    func planSprint(project: Int64, name: String, goal: String, start: Date, end: Date) async -> ServerAnswer? {
        let body = Schemas.NewSprintBody(
            endsOn: ProjectLogic.dayString(end), goal: goal, name: name, startsOn: ProjectLogic.dayString(start))
        return await act { try await client.planSprint(path: .init(id: project), body: .json(body)) }
    }

    /// An issue's runs, newest first.
    func issueRuns(company: Int64, issue: Int64) async -> [RunInfo]? {
        await read("listCompanyRuns") {
            guard
                case .ok(let ok) = try await client.listCompanyRuns(
                    path: .init(id: company), query: .init(issue: issue, limit: 20))
            else { return nil }
            return try ok.body.json.items.map(RunInfo.init)
        }
    }

    /// What happened to an issue, newest first (the audit log, filtered to it).
    func issueActivity(_ issue: Int64) async -> [AuditLine]? {
        await read("listAudit") {
            guard case .ok(let ok) = try await client.listAudit(query: .init(limit: 12, target: "issue:\(issue)"))
            else { return nil }
            return try ok.body.json.items.map(AuditLine.init)
        }
    }

    /// One repo's four commands (`updateRepo`); the repo as saved.
    func updateRepo(_ repo: RepoInfo) async -> Result<RepoInfo, ServerAnswer> {
        let forge = repo.tokenFile.map {
            Schemas.RepoForge(kind: repo.forgeKind ?? "github", repo: repo.name, tokenFile: $0)
        }
        let body = Schemas.RepoBody(
            commands: .init(build: repo.build, format: repo.format, lint: repo.lint, test: repo.test),
            defaultBranch: repo.defaultBranch, forge: forge, name: repo.name, url: repo.url)
        return await attempt({ try await client.updateRepo(path: .init(id: repo.id), body: .json(body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return RepoInfo(try ok.body.json)
        }
    }

    /// Re-homes a project on one team (the server keeps a single owning team).
    func setTeam(project: Int64, team: Int64) async -> ServerAnswer? {
        await act { try await client.updateProject(path: .init(id: project), body: .json(.init(teamId: team))) }
    }
}
