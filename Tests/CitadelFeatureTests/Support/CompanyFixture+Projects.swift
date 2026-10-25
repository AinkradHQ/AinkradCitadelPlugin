import Foundation

@testable import CitadelFeature

extension CompanyFixture {
    /// The Citadel project's work for the project page: an active sprint S4 with its burndown, a planned S5, epics,
    /// a backlog, velocity and capacity.
    static func projectWorkPage(_ model: CompanyModel) {
        projectsPage(model)
        let now = Date()
        let day: TimeInterval = 86_400
        func item(
            _ id: Int64, _ state: String, _ title: String, kind: String = "task", points: Int?, owner: Int64?,
            epic: Int64? = nil, sprint: Int64? = 4, rank: Double? = nil, high: Bool = false, run: Int64? = nil
        ) -> WorkItem {
            WorkItem(
                id: id, key: "CIT-\(id)", title: title, projectID: 1, state: state, kind: kind, priority: high,
                points: points, epicID: epic, sprintID: sprint, ownerAgentID: owner, checkoutRunID: run,
                rank: rank ?? Double(id))
        }
        var work = ProjectWork()
        work.epics = [
            EpicInfo(id: 1, key: "E-1", title: "Event stream", status: "open"),
            EpicInfo(id: 2, key: "E-2", title: "Runner leases", status: "open"),
            EpicInfo(id: 3, key: "E-3", title: "Plugin parity", status: "open"),
        ]
        work.sprints = [
            SprintDetail(
                id: 3, name: "S3", goal: "Wake queue", state: "closed", startsOn: now.addingTimeInterval(-24 * day),
                endsOn: now.addingTimeInterval(-11 * day)),
            SprintDetail(
                id: 4, name: "S4", goal: "Replay and leases land", state: "active",
                startsOn: now.addingTimeInterval(-5 * day), endsOn: now.addingTimeInterval(4 * day)),
            SprintDetail(
                id: 5, name: "S5", goal: "Plugin parity", state: "planned", startsOn: now.addingTimeInterval(7 * day),
                endsOn: now.addingTimeInterval(18 * day)),
        ]
        work.items = [
            item(
                42, "in_progress", "Event stream replay from last-seen id", kind: "story", points: 5, owner: 4, epic: 1,
                high: true, run: 418),
            item(61, "in_review", "Runner lease heartbeat", kind: "story", points: 8, owner: 9, epic: 2),
            item(64, "todo", "OpenAPI spec diff", points: 3, owner: 8, epic: 1),
            item(49, "blocked", "Wake queue coalescing", kind: "bug", points: 3, owner: 8, epic: 2),
            item(57, "done", "Approval expiry sweep", points: 5, owner: 4, epic: 1),
            item(58, "done", "Audit paging", points: 8, owner: 9, epic: 2),
            item(62, "todo", "Retry budget on runner_lost", kind: "bug", points: 3, owner: nil),
            item(
                70, "backlog", "Per-project spend scope", kind: "story", points: 5, owner: nil, epic: 3, sprint: nil,
                rank: 1),
            item(71, "backlog", "Probe endpoint for repos", points: 8, owner: nil, epic: 3, sprint: nil, rank: 2),
            item(72, "backlog", "CFD reporting", points: 5, owner: nil, sprint: nil, rank: 3),
            item(80, "todo", "Plugin parity pass", kind: "story", points: 5, owner: nil, epic: 3, sprint: 5),
        ]
        work.report = SprintReportInfo(
            sprintID: 4, committed: 34, completed: 13, capacity: 34, burndown: [34, 34, 30, 26, 21, 21])
        work.velocity = [
            VelocityPoint(sprintID: 1, committed: 28, completed: 24),
            VelocityPoint(sprintID: 2, committed: 30, completed: 30),
            VelocityPoint(sprintID: 3, committed: 32, completed: 29),
        ]
        work.velocityAverage = 27.7
        work.capacity = [4: 13, 9: 13, 8: 8]
        work.cycleDays = [1.2, 2.5, 3.1, 4, 4.5, 6.8, 2]
        work.throughput = [("W40", 3), ("W41", 5), ("W42", 4), ("W43", 6)]
        work.monthSpend = 18_400_000
        model.projectsPage.work[1] = work
        model.projectsPage.itemRuns[42] = [
            run(418, agent: 4, issue: 42, minutes: 4.2, tokens: 82_400, harness: "codex", model: "gpt-5.5")
        ]
    }

    static func projectPage(tab: ProjectTab, drawer: ProjectDrawer? = nil) -> (CompanyModel) -> Void {
        { model in
            projectWorkPage(model)
            model.projectsPage.openProject = 1
            model.projectsPage.tab = tab
            model.projectsPage.drawer = drawer
        }
    }
}
