import Foundation

/// Screen 12: the requirement hub's reads and the posts it sends.
extension CitadelStore {
    /// Opens a requirement: its thread and live plan, and the issues they name.
    func openRequirement(_ id: Int64) {
        guard let model, let server else { return }
        model.requirementsPage.isLoaded = true
        Task { await reloadThread(id, model: model, server: server, force: true) }
    }

    /// Reads a requirement's thread and plan again after its events (only once it was opened).
    func reloadThread(_ requirement: Int64, model: CompanyModel, server: CitadelServer) async {
        await reloadThread(requirement, model: model, server: server, force: false)
    }

    private func reloadThread(_ id: Int64, model: CompanyModel, server: CitadelServer, force: Bool) async {
        let page = model.requirementsPage
        guard force || page.threads[id] != nil else { return }
        async let thread = server.thread(requirement: id)
        async let plan = server.plan(requirement: id)
        if let thread = await thread { page.threads[id] = thread }
        if let plan = await plan { page.plans[id] = plan }
        // The keys the thread and the tree name, and the repos of tasks not yet in review ("2 repos").
        var issues = Set<Int64>()
        for item in page.threads[id]?.items ?? [] {
            switch item {
            case .message(let c, _): issues.insert(c.issueID)
            case .question(let q, _): issues.insert(q.issueID)
            case .approval(let a, _): if let issue = a.issueID { issues.insert(issue) }
            case .artifact(let a): if let issue = a.issueID { issues.insert(issue) }
            }
        }
        for issue in issues where model.issues[issue] == nil { model.issues[issue] = await server.issue(issue) }
        for task in page.plans[id]?.allTasks ?? [] where task.prs == 0 && model.issueRepos[task.issueID] == nil {
            guard task.state != "done", model.questions.contains(where: { $0.issueID == task.issueID }) else {
                continue
            }
            model.issueRepos[task.issueID] = await server.issueRepos(task.issueID)
        }
    }

    /// Sends the composer's text (or a quick reply): to the targeted question's asker, who is woken on its issue,
    /// or to the owner. The answered card becomes its receipt at once; the event refreshes the rest.
    func send(_ text: String, requirement: Int64, to target: ComposerTarget) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let model, let server else { return }
        let post = target.post
        Task {
            guard
                let answered = await server.post(
                    requirement: requirement, body: body, questionID: post.questionID, toOwner: post.toOwner)
            else { return }
            if let question = answered {
                model.requirementsPage.threads[requirement]?.answered(question, with: body)
                if let index = model.questions.firstIndex(where: { $0.id == question }) {
                    model.questions[index].state = "answered"
                }
            }
            model.requirementsPage.targetCleared = false
        }
    }

    /// ＋: a new requirement, as a request the CEO routes.
    func submitRequirement(title: String, body: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let server, let model else { return }
        Task { _ = await server.submitRequest(company: model.companyID, title: title, body: body) }
    }

    /// ▤ on a requirement: screen 13 filtered to it.
    func showArtifacts(requirement: Int64) {
        model?.artifactsPage.filter = ArtifactFilter(requirementID: requirement)
        screen = .artifacts
    }
}
