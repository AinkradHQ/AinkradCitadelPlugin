import CitadelClient
import Foundation

/// The approvals inbox (06) and agent threads (07): their extra reads and the actions they send.
extension CitadelStore {
    /// "Reply only": your reply as a comment on the approval's issue, which wakes the asker without deciding.
    func replyOnly(_ approval: ApprovalInfo, text: String) {
        guard let issue = approval.issueID else { return }
        send(text, on: issue)
    }

    /// Sends a message in an agent thread: a comment on the issue. It answers the issue's newest open question
    /// (and clears its card in the requirement thread too) and wakes the agent.
    func send(_ text: String, on issue: Int64) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let server, let model else { return }
        Task {
            guard let comment = await server.postComment(issue: issue, body: body) else { return }
            model.posted(comment)
        }
    }

    /// Opens an agent thread: the issue's comments, and the agent's runs for the run lines between them.
    func openThread(_ thread: ThreadKey) {
        guard let server, let model else { return }
        Task {
            if let comments = await server.comments(issue: thread.issueID) { model.comments[thread.issueID] = comments }
            if let runs = await server.agentRuns(thread.agentID, limit: 50) { model.agentRuns[thread.agentID] = runs }
            if let info = await server.issue(thread.issueID) { model.issues[thread.issueID] = info }
        }
    }

    /// The selected sprint commit's velocity (its project's last sprints).
    func loadVelocity(project: Int64) {
        guard let server, let model, model.velocity[project] == nil else { return }
        Task { model.velocity[project] = await server.velocity(project: project) }
    }

    /// Decided approvals for the inbox's "Answered" section, newest first.
    func loadAnswered(_ model: CompanyModel, server: CitadelServer) async {
        guard let all = await server.approvals(company: model.companyID, pending: false) else { return }
        model.answeredApprovals = Array(all.filter { $0.status != "pending" }.sorted { $0.id > $1.id }.prefix(10))
    }

    /// Agents' questions: the open ones from every issue (`GET /companies/{id}/questions`), and the answered ones
    /// the requirement threads keep as receipts. Should the open list fail, the threads' open cards stand in.
    func loadQuestions(_ model: CompanyModel, server: CitadelServer) async {
        let open = await server.openQuestions(company: model.companyID)
        var byID: [Int64: QuestionInfo] = [:]
        for requirement in model.requirements {
            for question in await server.questions(requirement: requirement.id) ?? []
            where open == nil || !question.isOpen {
                byID[question.id] = question
            }
        }
        for question in open ?? [] { byID[question.id] = question }
        let questions = byID.values.sorted { ($0.askedAt, $0.id) < ($1.askedAt, $1.id) }
        model.questions = questions
        for issue in Set(questions.map(\.issueID)) where model.issues[issue] == nil {
            model.issues[issue] = await server.issue(issue)
        }
    }
}
