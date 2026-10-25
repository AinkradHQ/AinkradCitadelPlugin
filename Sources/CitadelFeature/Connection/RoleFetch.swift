import CitadelClient
import Foundation

/// Company roles (API minor 18).
extension CitadelServer {
    func roles(company: Int64) async -> [RoleInfo]? {
        await read("listRoles") {
            guard case .ok(let ok) = try await client.listRoles(path: .init(id: company)) else { return nil }
            return try ok.body.json.map(RoleInfo.init)
        }
    }

    func createRole(company: Int64, _ role: RoleInfo) async -> Result<RoleInfo, ServerAnswer> {
        await attempt({ try await client.createRole(path: .init(id: company), body: .json(role.body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return RoleInfo(try ok.body.json)
        }
    }

    func updateRole(_ role: RoleInfo) async -> Result<RoleInfo, ServerAnswer> {
        await attempt({ try await client.updateRole(path: .init(id: role.id), body: .json(role.body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return RoleInfo(try ok.body.json)
        }
    }

    func deleteRole(_ id: Int64) async -> ServerAnswer? {
        await act { try await client.deleteRole(path: .init(id: id)) }
    }
}
