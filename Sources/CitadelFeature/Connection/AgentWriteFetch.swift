import CitadelClient
import Foundation

/// What an edit of one agent changes (API minor 17); every `nil` stays as it is on the server.
struct AgentPatch: Equatable, Sendable {
    var role: String?
    var harness: String?
    var model: String?
    var effort: String?
    var sandbox: String?
    var runnerTags: [String]?
    var reportsTo: Int64?
    var about: String?
    var instructions: String?
    var guidelines: [String]?

    var body: Schemas.AgentUpdate {
        .init(
            description: about.map { String($0.prefix(4000)) },
            effort: effort.map { .init(value1: .init(rawValue: $0), value2: $0) },
            guidelines: guidelines.map(AgentDraft.cleanGuidelines),
            harness: harness.map { .init(value1: .init(rawValue: $0), value2: $0) },
            instructions: instructions.map { String($0.prefix(20_000)) }, model: model, reportsTo: reportsTo,
            role: role, runnerTags: runnerTags,
            sandbox: sandbox.map { .init(value1: .init(rawValue: $0), value2: $0) })
    }
}

/// Agent edits, wake and terminate (API minor 17). An older server answers 404; the screens gate on the minor.
extension CitadelServer {
    /// `PATCH /agents/{id}`: the agent as stored after.
    func update(agent: Int64, _ patch: AgentPatch) async -> Result<Schemas.Agent, ServerAnswer> {
        await attempt({ try await client.updateAgent(path: .init(id: agent), body: .json(patch.body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return try ok.body.json
        }
    }

    /// "Wake now": the agent is woken on each open issue waiting on it, else once to look at its inbox.
    func wake(agent: Int64) async -> Result<Schemas.Agent, ServerAnswer> {
        await attempt({ try await client.wakeAgent(path: .init(id: agent)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return try ok.body.json
        }
    }

    /// Lets the agent go for good; `reason` is kept in the audit trail.
    func terminate(agent: Int64, reason: String) async -> Result<Schemas.Agent, ServerAnswer> {
        await attempt({ try await client.terminateAgent(path: .init(id: agent), body: .json(.init(reason: reason))) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return try ok.body.json
        }
    }
}
