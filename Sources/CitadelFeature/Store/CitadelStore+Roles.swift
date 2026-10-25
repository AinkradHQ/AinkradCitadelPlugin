import AinkradAppKit
import Foundation

/// Company roles (API minor 18): the Roles tab's writes and the list the hire wizard's role grid reads. Below 18
/// nothing is read or written and the wizard keeps its built-in roles.
extension CitadelStore {
    var rolesOn: Bool { serverSupports(minor: Self.trancheBMinor) }

    func loadRoles() {
        guard rolesOn, let server, let model else { return }
        Task { await reloadRoles(model, server: server) }
    }

    func reloadRoles(_ model: CompanyModel, server: CitadelServer) async {
        guard rolesOn, let roles = await server.roles(company: model.companyID) else { return }
        model.roles = roles
    }

    /// Creates (`isNew`) or replaces a role; `done` runs once the server took it.
    func saveRole(_ role: RoleInfo, isNew: Bool, done: @escaping @MainActor () -> Void) {
        guard rolesOn, let server, let model else { return }
        var role = role
        role.name = role.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !role.name.isEmpty else { return }
        Task {
            let result =
                isNew ? await server.createRole(company: model.companyID, role) : await server.updateRole(role)
            switch result {
            case .success(let saved):
                actionFailure = nil
                done()
                toast(
                    AinkradRichToast(
                        title: isNew ? "\(saved.name) added" : "\(saved.name) saved",
                        body: "The hire wizard offers it as a role.", status: .success))
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: isNew ? "Couldn't add \(role.name)" : "Couldn't save \(role.name)", answer: answer,
                    outcome: isNew ? "No role was added." : "The role is unchanged.")
            }
            await reloadRoles(model, server: server)
        }
    }

    func deleteRole(_ role: RoleInfo, done: @escaping @MainActor () -> Void) {
        guard rolesOn, let server, let model else { return }
        Task {
            if let answer = await server.deleteRole(role.id) {
                actionFailure = ActionFailure(
                    title: "Couldn't delete \(role.name)", answer: answer, outcome: "The role is still there.")
            } else {
                done()
                toast(AinkradRichToast(title: "\(role.name) deleted", status: .success))
            }
            await reloadRoles(model, server: server)
        }
    }
}
