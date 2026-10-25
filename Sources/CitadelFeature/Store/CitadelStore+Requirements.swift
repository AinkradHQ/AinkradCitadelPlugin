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
    /// `extras` (project, priority, criteria) go as fields from API minor 18; an older server gets none of them.
    func submitRequirement(title: String, body: String, extras: RequestExtras? = nil) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, let server, let model else { return }
        let extras = hasTrancheB ? extras : nil
        Task { _ = await server.submitRequest(company: model.companyID, title: title, body: body, extras: extras) }
    }

    /// "⋯ → Rename…": the hub's list and the thread's title follow.
    func rename(requirement: RequirementInfo, to title: String) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != requirement.title else { return }
        requirementWrite(requirement.id, "Couldn't rename \(requirement.key)", outcome: "Its title is unchanged.") {
            await $0.rename(requirement: requirement.id, title: title)
        } done: { model in
            if let index = model.requirements.firstIndex(where: { $0.id == requirement.id }) {
                model.requirements[index].title = title
            }
        }
    }

    /// "⋯ → Cancel requirement…": it and its open issues are cancelled; it leaves the hub's list.
    func cancel(requirement: RequirementInfo, reason: String) {
        let reason = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        requirementWrite(
            requirement.id, "Couldn't cancel \(requirement.key)", outcome: "It and its issues go on."
        ) {
            await $0.cancel(requirement: requirement.id, reason: reason.isEmpty ? nil : reason)
        } done: { model in
            if let index = model.requirements.firstIndex(where: { $0.id == requirement.id }) {
                model.requirements[index].state = "cancelled"
            }
        }
    }

    /// 📎: the file goes into the thread as an artifact card.
    func attach(_ file: URL, requirement: RequirementInfo) {
        guard let data = try? Data(contentsOf: file) else {
            actionFailure = ActionFailure(
                title: "Couldn't read \(file.lastPathComponent)",
                answer: ServerAnswer(status: 0, code: "unreadable", message: "the file could not be read"),
                outcome: "Nothing was attached.")
            return
        }
        let name = file.lastPathComponent
        requirementWrite(requirement.id, "Couldn't attach \(name)", outcome: "Nothing was attached.") {
            await $0.attach(requirement: requirement.id, name: name, data: data)
        } done: { _ in
        }
    }

    func requirementWrite(
        _ id: Int64, _ title: String, outcome: String, _ send: @escaping (CitadelServer) async -> ServerAnswer?,
        done: @escaping @MainActor (CompanyModel) -> Void
    ) {
        guard let server, let model else { return }
        Task {
            if let answer = await send(server) {
                actionFailure = ActionFailure(title: title, answer: answer, outcome: outcome)
            } else {
                actionFailure = nil
                done(model)
                schedule([.requirements, .thread(id), .artifacts])
            }
        }
    }

    /// ▤ on a requirement: screen 13 filtered to it.
    func showArtifacts(requirement: Int64) {
        model?.artifactsPage.filter = ArtifactFilter(requirementID: requirement)
        screen = .artifacts
    }
}
