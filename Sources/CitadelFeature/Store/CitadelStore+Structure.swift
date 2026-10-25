import AinkradAppKit
import Foundation

/// Org → Structure writes of API minor 17: departments, teams and their seats. Each does nothing on an older
/// server (the sheets keep their buttons off there); a refusal opens the failure card with the server's words.
extension CitadelStore {
    private func structureFailed(_ title: String, _ answer: ServerAnswer, _ outcome: String) {
        actionFailure = ActionFailure(title: title, answer: answer, outcome: outcome)
        schedule([.org])
    }

    private func structureDone(_ title: String, _ body: String? = nil) {
        toast(AinkradRichToast(title: title, body: body, status: .success))
        schedule([.org])
    }

    /// Creates (`id == nil`) or changes a department; `done` runs once the server took it.
    func saveDepartment(
        _ id: Int64?, name: String, about: String, head: Int64?, done: @escaping @MainActor () -> Void
    ) {
        guard serverSupports(minor: Self.structureMinor), let server, let company = model?.companyID else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        Task {
            if let id {
                switch await server.updateDepartment(id, name: name, about: about, head: head) {
                case .success:
                    done()
                    structureDone("\(name) saved")
                case .failure(let answer):
                    structureFailed("Couldn't save \(name)", answer, "The department is unchanged.")
                }
            } else {
                switch await server.createDepartment(company: company, name: name, about: about, head: head) {
                case .success:
                    done()
                    structureDone("\(name) created", "Add teams to it from Structure.")
                case .failure(let answer):
                    structureFailed("Couldn't create \(name)", answer, "No department was added.")
                }
            }
        }
    }

    func deleteDepartment(_ department: DepartmentInfo, done: @escaping @MainActor () -> Void) {
        guard serverSupports(minor: Self.structureMinor), let server else { return }
        Task {
            if let answer = await server.deleteDepartment(department.id) {
                structureFailed("Couldn't delete \(department.name)", answer, "The department is still there.")
            } else {
                done()
                structureDone("\(department.name) deleted")
            }
        }
    }

    /// Creates (`current == nil`) or changes a team: its name, its department and its lead (a `team_lead` seat; the
    /// old lead steps down to member first, since a team has one).
    func saveTeam(
        _ current: TeamInfo?, name: String, department: Int64, lead: Int64?, done: @escaping @MainActor () -> Void
    ) {
        guard serverSupports(minor: Self.structureMinor), let server, let model else { return }
        let name = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty, department != 0 else { return }
        let title = current == nil ? "Couldn't create \(name)" : "Couldn't save \(name)"
        Task {
            var team: TeamInfo
            if let current {
                let old = model.departments.first { $0.teams.contains { $0.id == current.id } }?.id
                team = current
                if name != current.name || department != old {
                    switch await server.updateTeam(
                        current.id, name: name != current.name ? name : nil,
                        department: department != old ? department : nil)
                    {
                    case .success(let saved): team = saved
                    case .failure(let answer): return structureFailed(title, answer, "The team is unchanged.")
                    }
                }
            } else {
                switch await server.createTeam(department: department, name: name) {
                case .success(let created): team = created
                case .failure(let answer): return structureFailed(title, answer, "No team was added.")
                }
            }
            let oldLead = team.seats.first { $0.teamRole == "team_lead" }?.agentID
            if let lead, lead != oldLead {
                if let oldLead, case .failure(let answer) = await server.seat(agent: oldLead, in: team.id, as: "member")
                {
                    return structureFailed(title, answer, "The team's lead is unchanged.")
                }
                if case .failure(let answer) = await server.seat(agent: lead, in: team.id, as: "team_lead") {
                    return structureFailed(title, answer, "The team has no new lead.")
                }
            }
            done()
            structureDone(current == nil ? "\(name) created" : "\(name) saved")
        }
    }

    /// Deletes the team with its seats; its agents stay in the company, unseated.
    func deleteTeam(_ team: TeamInfo, done: @escaping @MainActor () -> Void) {
        guard serverSupports(minor: Self.structureMinor), let server else { return }
        Task {
            if let answer = await server.deleteTeam(team.id) {
                structureFailed("Couldn't delete \(team.name)", answer, "The team is still there.")
            } else {
                done()
                structureDone("\(team.name) deleted", "Its agents are unseated; its projects have no team.")
            }
        }
    }

    /// Takes an agent off a team.
    func unseat(_ agent: AgentInfo, from team: TeamInfo) {
        guard serverSupports(minor: Self.structureMinor), let server else { return }
        Task {
            switch await server.unseat(agent: agent.id, from: team.id) {
            case .success: structureDone("\(agent.name) left \(team.name)")
            case .failure(let answer):
                structureFailed("Couldn't unseat \(agent.name)", answer, "\(agent.name) keeps the seat.")
            }
        }
    }
}
