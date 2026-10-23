import Foundation

/// 11 A and the org's ＋: hires go through approvals, so a sent hire opens the inbox where they wait.
extension CitadelStore {
    /// "Use Engineering template": a CTO and one scrum team, each a hire to approve.
    func useTemplate(_ template: String = "engineering") {
        guard let server, let company = model?.companyID else { return }
        Task {
            switch await server.applyTemplate(company: company, template) {
            case .success:
                actionFailure = nil
                schedule([.org, .approvals])
                screen = .approvals
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: "Couldn't apply the \(template) template", answer: answer, outcome: "Nobody was proposed.")
            }
        }
    }

    /// "Propose an agent…": its hire approval waits in the inbox; `done` runs once the server took it.
    func proposeAgent(_ draft: AgentDraft, done: @escaping @MainActor () -> Void) {
        guard draft.problem == nil, let server, let company = model?.companyID else { return }
        Task {
            switch await server.proposeAgent(company: company, draft) {
            case .success:
                actionFailure = nil
                done()
                schedule([.org, .approvals])
                screen = .approvals
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: "Couldn't propose \(draft.name)", answer: answer, outcome: "Nobody was proposed.")
            }
        }
    }
}
