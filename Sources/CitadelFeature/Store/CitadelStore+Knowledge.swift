import Foundation

/// The project screen's Knowledge group (API minor 16): accept or reject a proposal, retire or supersede an accepted
/// entry. A refusal becomes `actionFailure`; a write reads the project's knowledge (and profile) again.
extension CitadelStore {
    func reloadKnowledge(_ project: Int64, model: CompanyModel, server: CitadelServer) async {
        if let entries = await server.knowledge(project: project) { model.projectsPage.knowledge[project] = entries }
    }

    func decide(_ entry: KnowledgeInfo, project: Int64, accept: Bool, reason: String? = nil) {
        let reason = (reason?.trimmingCharacters(in: .whitespacesAndNewlines)).nonEmpty
        knowledgeWrite(
            project, "Couldn't \(accept ? "accept" : "reject") \(entry.title)", outcome: "It is still proposed."
        ) { await $0.decide(knowledge: entry.id, accept: accept, reason: reason) }
    }

    func retire(_ entry: KnowledgeInfo, project: Int64, reason: String) {
        knowledgeWrite(project, "Couldn't retire \(entry.title)", outcome: "Runs are still given it.") {
            await $0.retire(knowledge: entry.id, reason: reason)
        }
    }

    func supersede(_ entry: KnowledgeInfo, project: Int64, body: String, reason: String? = nil) {
        let reason = (reason?.trimmingCharacters(in: .whitespacesAndNewlines)).nonEmpty
        knowledgeWrite(project, "Couldn't supersede \(entry.title)", outcome: "It stays as it was.") {
            await $0.supersede(knowledge: entry.id, title: nil, body: body, reason: reason)
        }
    }

    private func knowledgeWrite(
        _ project: Int64, _ title: String, outcome: String, _ work: @escaping (CitadelServer) async -> ServerAnswer?
    ) {
        guard let server, let model else { return }
        perform(
            title, outcome: outcome,
            done: {
                Task {
                    await self.reloadKnowledge(project, model: model, server: server)
                    await self.reloadProfile(project, model: model, server: server)
                }
            }, work)
    }
}
