import Foundation

/// The agent thread's issue controls (API minors 12–14): blockers, blocking on one, the issue's sprint (an active
/// sprint's scope too), deleting an empty planned sprint, and whom a message wakes. A refusal becomes
/// `actionFailure` (mockup 11 G); a write reads the issue and its lists again.
extension CitadelStore {
    func linkBlocker(_ issue: IssueInfo, blocker: IssueInfo) {
        issueWrite(issue, "Couldn't link \(blocker.key) as blocking \(issue.key)", outcome: "Nothing was linked.") {
            await $0.linkBlocker(issue: issue.id, blocker: blocker.id)
        }
    }

    func unlinkBlocker(_ issue: IssueInfo, blocker: IssueInfo) {
        issueWrite(issue, "Couldn't unlink \(blocker.key)", outcome: "It still blocks \(issue.key).") {
            await $0.unlinkBlocker(issue: issue.id, blocker: blocker.id)
        }
    }

    /// Blocks the issue on `blocker`, linking it in the same step.
    func block(_ issue: IssueInfo, on blocker: IssueInfo) {
        issueWrite(issue, "Couldn't block \(issue.key) on \(blocker.key)", outcome: "Its state is unchanged.") {
            await $0.block(issue: issue.id, on: blocker.id)
        }
    }

    /// Moves the issue into `sprint` (an active one changes its committed scope), or out of its sprint.
    func setSprint(_ issue: IssueInfo, to sprint: ProjectSprintInfo?) {
        let title =
            sprint.map { "Couldn't add \(issue.key) to \($0.name)" } ?? "Couldn't take \(issue.key) out of its sprint"
        issueWrite(issue, title, outcome: "Its sprint is unchanged.") {
            await $0.setSprint(issue: issue.id, sprint: sprint?.id)
        }
    }

    /// Deletes an empty planned sprint.
    func deleteSprint(_ sprint: ProjectSprintInfo, of issue: IssueInfo) {
        issueWrite(issue, "Couldn't delete \(sprint.name)", outcome: "Nothing was deleted.") {
            await $0.deleteSprint(sprint.id)
        }
    }

    private func issueWrite(
        _ issue: IssueInfo, _ title: String, outcome: String, _ work: @escaping (CitadelServer) async -> ServerAnswer?
    ) {
        guard let server, let model else { return }
        perform(
            title, outcome: outcome,
            done: {
                Task { await self.refreshIssueWork(issue.id, project: issue.projectID, model: model, server: server) }
            }, work)
    }

    /// The issue, its blockers, and its project's sprints and issues (the thread's menus).
    func refreshIssueWork(_ issue: Int64, project: Int64, model: CompanyModel, server: CitadelServer) async {
        if let info = await server.issue(issue) { model.issues[issue] = info }
        if let blockers = await server.blockers(issue: issue) { model.blockers[issue] = blockers }
        if let sprints = await server.sprints(project: project) { model.projectSprints[project] = sprints }
        if let issues = await server.projectIssues(project) {
            model.projectIssues[project] = issues
            for info in issues where model.issues[info.id] != nil { model.issues[info.id] = info }
        }
    }
}
