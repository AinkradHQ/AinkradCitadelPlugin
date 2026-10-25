import AinkradAppKit
import Foundation

/// Agent writes of API minor 17: edit (`PATCH /agents/{id}`), wake now, terminate. Each is a no-op on an older
/// server — the controls are off there — so nothing ever reaches an endpoint that would answer 404.
extension CitadelStore {
    /// Saves `patch`; a toast confirms it with `title`, `done` runs once the server took it.
    func edit(
        _ agent: AgentInfo, _ patch: AgentPatch, title: String, body: String? = nil,
        done: @escaping @MainActor () -> Void = {}
    ) {
        guard serverSupports(minor: Self.structureMinor), let server else { return }
        Task {
            switch await server.update(agent: agent.id, patch) {
            case .success(let saved):
                model?.agents[agent.id]?.merge(saved)
                done()
                agentToast(model?.agents[agent.id] ?? agent, title: title, body: body)
                schedule([.org])
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: "Couldn't update \(agent.name)", answer: answer, outcome: "Nothing was changed.")
            }
        }
    }

    /// "Wake now": the agent runs on what is waiting for it.
    func wake(_ agent: AgentInfo) {
        guard serverSupports(minor: Self.structureMinor), let server else { return }
        Task {
            switch await server.wake(agent: agent.id) {
            case .success:
                agentToast(agent, title: "\(agent.name) woken", body: "It picks up what is waiting for it.")
                schedule([.org, .agent(agent.id), .agentRun(agent.id)])
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: "Couldn't wake \(agent.name)", answer: answer, outcome: "It was not woken.")
            }
        }
    }

    /// Lets the agent go (the sheet confirmed); its runs end, its issues return to the team queue.
    func terminate(_ agent: AgentInfo, reason: String) {
        guard serverSupports(minor: Self.structureMinor), let server else { return }
        let why = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        Task {
            switch await server.terminate(agent: agent.id, reason: why.isEmpty ? "terminated from the app" : why) {
            case .success(let saved):
                model?.agents[agent.id]?.merge(saved)
                detail = nil
                agentToast(
                    agent, title: "\(agent.name) terminated", body: "Its issues return to the team queue.",
                    status: .warning)
                schedule([.org, .approvals])
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: "Couldn't terminate \(agent.name)", answer: answer, outcome: "It is still on the team.")
            }
        }
    }
}
