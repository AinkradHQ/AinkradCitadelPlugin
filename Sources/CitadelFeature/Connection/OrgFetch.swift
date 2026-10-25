import CitadelClient
import Foundation

/// What the org, agent and hire screens read and write beyond the org chart: an agent's palette (decision #61),
/// its resolved skills.
extension CitadelServer {
    /// Recolours the agent's figure; the agent as stored after.
    func setPalette(agent: Int64, _ palette: String) async -> ServerAnswer? {
        await act { try await client.setAppearance(path: .init(id: agent), body: .json(.init(paletteId: palette))) }
    }

    /// The skills a run of this agent loads, resolved from company, department, role and project attachments.
    func agentSkills(_ agent: Int64) async -> [SkillInfo]? {
        await read("listAgentSkills") {
            guard case .ok(let ok) = try await client.listAgentSkills(path: .init(id: agent)) else { return nil }
            return try ok.body.json.map(SkillInfo.init)
        }
    }
}
