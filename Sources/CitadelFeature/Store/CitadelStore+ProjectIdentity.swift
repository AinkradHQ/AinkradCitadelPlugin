import AinkradAppKit
import AppKit
import CitadelClient
import Foundation
import Observation

/// The projects' uploaded logos by project id (`GET /projects/{id}/logo`, API minor 18).
@MainActor
@Observable
final class ProjectLogos {
    var images: [Int64: NSImage] = [:]
}

/// The project page's identity, teams and runtime (API minor 18): logo, several teams with an owner, runner limits,
/// the network host list and the definition of done's on/off rules. Every write is gated on the server's minor; an
/// older server is sent nothing and its screen keeps today's controls.
extension CitadelStore {
    /// Reads the logo of each project that has one; an older server has none.
    func loadProjectLogos(using server: CitadelServer) {
        guard hasTrancheB, let model else { return }
        for project in model.projects where project.logoURL != nil && projectLogos.images[project.id] == nil {
            Task {
                if let data = await server.projectLogo(project.id), let image = NSImage(data: data) {
                    projectLogos.images[project.id] = image
                }
            }
        }
    }

    func setProjectLogo(_ data: Data, type: String, project: ProjectInfo) {
        guard hasTrancheB, let server else { return }
        Task {
            switch await server.uploadProjectLogo(project.id, data: data, type: type) {
            case .success(let fresh):
                projectLogos.images[project.id] = NSImage(data: data)
                replace(fresh)
            case .failure(let answer):
                toast(
                    AinkradRichToast(
                        title: "Couldn't upload \(project.key)'s logo", body: answer.message, status: .danger))
            }
        }
    }

    func removeProjectLogo(_ project: ProjectInfo) {
        guard hasTrancheB, let server else { return }
        Task {
            switch await server.resetProjectLogo(project.id) {
            case .success(let fresh):
                projectLogos.images[project.id] = nil
                replace(fresh)
            case .failure(let answer):
                toast(
                    AinkradRichToast(
                        title: "Couldn't remove \(project.key)'s logo", body: answer.message, status: .danger))
            }
        }
    }

    /// Teams: tapping a team attaches it (after the others) or detaches it; the first stays the owner.
    func toggleTeam(_ team: TeamInfo, project: ProjectInfo) {
        var ids = project.allTeamIDs
        if let index = ids.firstIndex(of: team.id) {
            guard ids.count > 1 else {
                return toast(
                    AinkradRichToast(
                        title: "\(project.key) needs a team", body: "Attach another before detaching \(team.name).",
                        status: .warning))
            }
            ids.remove(at: index)
        } else {
            ids.append(team.id)
        }
        saveTeams(ids, project: project, team: team)
    }

    /// "Make owner": the team goes first; its lead plans sprints with the PO.
    func makeOwner(_ team: TeamInfo, project: ProjectInfo) {
        saveTeams([team.id] + project.allTeamIDs.filter { $0 != team.id }, project: project, team: team)
    }

    private func saveTeams(_ ids: [Int64], project: ProjectInfo, team: TeamInfo) {
        guard hasTrancheB else { return setTeam(team, project: project) }
        saveProject(project, .init(teamIds: ids), failure: "Couldn't change the teams on \(project.key)")
    }

    /// Runtime: the tags a runner needs, parallel runs, the run timeout (seconds) and how long worktrees are kept.
    func setRuntime(
        _ project: ProjectInfo, tags: [String]? = nil, parallel: Int? = nil, timeoutSecs: Int? = nil,
        keepDays: Int? = nil
    ) {
        guard hasTrancheB else { return }
        let settings = Schemas.ProjectSettings(
            maxParallelRuns: parallel.map(Int32.init), runTimeoutSecs: timeoutSecs.map(Int32.init),
            runnerTags: tags, worktreeKeepDays: keepDays.map(Int32.init))
        saveProject(project, settings, failure: "Couldn't change \(project.key)'s runtime")
    }

    /// Network: the hosts agents reach without asking.
    func setNetworkHosts(project: Int64, _ hosts: [String]) {
        guard hasTrancheB else { return }
        updateProfile(project: project, Schemas.ProfilePatch(networkHosts: hosts))
    }

    /// Rules: the definition of done as rules, each on or off (QA checks the ones that are on).
    func setDoneRules(project: Int64, _ rules: [DodRuleInfo]) {
        guard hasTrancheB else { return }
        updateProfile(
            project: project,
            Schemas.ProfilePatch(definitionOfDoneRules: rules.map { Schemas.DodRule(on: $0.on, text: $0.text) }))
    }

    private func saveProject(_ project: ProjectInfo, _ settings: Schemas.ProjectSettings, failure: String) {
        guard let server else { return }
        Task {
            switch await server.updateProject(project.id, settings) {
            case .success(let fresh): replace(fresh)
            case .failure(let answer): toast(AinkradRichToast(title: failure, body: answer.message, status: .danger))
            }
        }
    }

    private func replace(_ project: ProjectInfo) {
        guard let model, let index = model.projects.firstIndex(where: { $0.id == project.id }) else { return }
        model.projects[index] = project
    }
}
