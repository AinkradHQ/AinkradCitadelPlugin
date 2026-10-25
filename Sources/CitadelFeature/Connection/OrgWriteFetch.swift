import CitadelClient
import Foundation

/// Org structure writes (API minor 17): departments, teams and seats. An older server answers 404; the sheets gate
/// on the minor so these are never called there. Roles have no server resource, so there is no role write.
extension CitadelServer {
    func createDepartment(company: Int64, name: String, about: String, head: Int64?) async -> Result<
        DepartmentInfo, ServerAnswer
    > {
        await attempt({
            try await client.createDepartment(
                path: .init(id: company), body: .json(.init(about: about, headAgentId: head, name: name)))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            return DepartmentInfo(try ok.body.json)
        }
    }

    /// `nil` fields stay as they are (a head cannot be cleared from here).
    func updateDepartment(_ id: Int64, name: String?, about: String?, head: Int64?) async -> Result<
        DepartmentInfo, ServerAnswer
    > {
        await attempt({
            try await client.updateDepartment(
                path: .init(id: id), body: .json(.init(about: about, headAgentId: head, name: name)))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            return DepartmentInfo(try ok.body.json)
        }
    }

    /// Refused with 409 while it still has teams.
    func deleteDepartment(_ id: Int64) async -> ServerAnswer? {
        await act { try await client.deleteDepartment(path: .init(id: id)) }
    }

    func createTeam(department: Int64, name: String) async -> Result<TeamInfo, ServerAnswer> {
        await attempt({ try await client.createTeam(path: .init(id: department), body: .json(.init(name: name))) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return TeamInfo(try ok.body.json)
        }
    }

    func updateTeam(_ id: Int64, name: String?, department: Int64?) async -> Result<TeamInfo, ServerAnswer> {
        await attempt({
            try await client.updateTeam(path: .init(id: id), body: .json(.init(departmentId: department, name: name)))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            return TeamInfo(try ok.body.json)
        }
    }

    /// Deletes the team with its seats.
    func deleteTeam(_ id: Int64) async -> ServerAnswer? {
        await act { try await client.deleteTeam(path: .init(id: id)) }
    }

    /// Seats the agent (or changes its seat); 409 when another agent is the team's product owner or lead.
    func seat(agent: Int64, in team: Int64, as role: String) async -> Result<TeamInfo, ServerAnswer> {
        await attempt({
            try await client.seatAgent(
                path: .init(id: team, agentId: agent),
                body: .json(.init(teamRole: .init(value1: .init(rawValue: role), value2: role))))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            return TeamInfo(try ok.body.json)
        }
    }

    func unseat(agent: Int64, from team: Int64) async -> Result<TeamInfo, ServerAnswer> {
        await attempt({ try await client.unseatAgent(path: .init(id: team, agentId: agent)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return TeamInfo(try ok.body.json)
        }
    }
}
