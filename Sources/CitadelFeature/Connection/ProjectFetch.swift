import CitadelClient
import Foundation

/// Screen 14's reads and writes: a project's profile and its repos (E15.13, E15.16).
extension CitadelServer {
    func repos(project: Int64) async -> [RepoInfo]? {
        await read("listRepos") {
            guard case .ok(let ok) = try await client.listRepos(path: .init(id: project)) else { return nil }
            return try ok.body.json.map(RepoInfo.init)
        }
    }

    func profile(project: Int64) async -> ProfileInfo? {
        await read("getProjectProfile") {
            guard case .ok(let ok) = try await client.getProjectProfile(path: .init(id: project)) else { return nil }
            return ProfileInfo(try ok.body.json)
        }
    }

    /// Changes only the fields `patch` gives; the profile after.
    func updateProfile(project: Int64, _ patch: Schemas.ProfilePatch) async -> ProfileInfo? {
        await read("updateProjectProfile") {
            guard
                case .ok(let ok) = try await client.updateProjectProfile(
                    path: .init(id: project), body: .json(patch))
            else { return nil }
            return ProfileInfo(try ok.body.json)
        }
    }

    /// The project's active sprint's name, if it has one.
    func activeSprintName(project: Int64) async -> String? {
        await read("listSprints") {
            guard case .ok(let ok) = try await client.listSprints(path: .init(id: project)) else { return nil }
            return try ok.body.json.last { $0.state.word == "active" }?.name
        }
    }

    /// The project's issues being worked on now.
    func activeIssues(project: Int64) async -> [IssueInfo]? {
        await read("listProjectIssues") {
            guard case .ok(let ok) = try await client.listProjectIssues(path: .init(id: project)) else { return nil }
            return try ok.body.json.filter { ["in_progress", "in_review"].contains($0.state.word) }.map(IssueInfo.init)
        }
    }

    /// Sets the merge order (decision #54): every repo's name, in the new order. The repos as the server keeps them.
    func orderRepos(project: Int64, names: [String]) async -> Result<[RepoInfo], ServerAnswer> {
        await attempt({ try await client.orderRepos(path: .init(id: project), body: .json(.init(repos: names))) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return try ok.body.json.map(RepoInfo.init)
        }
    }

    /// ★: makes `repo` the project's primary (the default for new issues).
    func setPrimary(repo: Int64) async -> Result<[RepoInfo], ServerAnswer> {
        await attempt({ try await client.setPrimaryRepo(path: .init(id: repo)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return try ok.body.json.map(RepoInfo.init)
        }
    }

    /// ✕: refused (400, with the server's reason) while an open issue touches it, or for the primary while there
    /// are others. The repos left.
    func removeRepo(_ repo: Int64) async -> Result<[RepoInfo], ServerAnswer> {
        await attempt({ try await client.removeRepo(path: .init(id: repo)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return try ok.body.json.map(RepoInfo.init)
        }
    }

    /// "＋ Add repository": the server checks the URL and the token reference before it saves.
    func addRepo(project: Int64, _ body: Schemas.RepoBody) async -> Result<RepoInfo, ServerAnswer> {
        await attempt({ try await client.addRepo(path: .init(id: project), body: .json(body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return RepoInfo(try ok.body.json)
        }
    }
}

/// Screen 14's API minor 7 writes: a new project, a decision on an agent's proposal, and the profile's history.
extension CitadelServer {
    /// "＋ New project": a malformed or taken key is a 409 with the server's reason.
    func createProject(company: Int64, name: String, key: String, mode: String, team: Int64? = nil) async -> Result<
        ProjectInfo, ServerAnswer
    > {
        let body = Schemas.NewProject(
            key: key, mode: .init(value1: .init(rawValue: mode), value2: mode), name: name, teamId: team)
        return await attempt({ try await client.createProject(path: .init(id: company), body: .json(body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return ProjectInfo(try ok.body.json)
        }
    }

    /// Accept applies the proposal; reject drops it, with an optional reason (decision #48: a person only). The
    /// profile after.
    func decide(proposal: Int64, project: Int64, accept: Bool, reason: String?) async -> Result<
        ProfileInfo, ServerAnswer
    > {
        await attempt({
            try await client.decideProfileProposal(
                path: .init(id: project, proposalId: proposal), body: .json(.init(accept: accept, reason: reason)))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            return ProfileInfo(try ok.body.json)
        }
    }

    /// The profile's changes and the agents' proposals of them, newest first.
    func profileHistory(project: Int64, limit: Int32 = 50) async -> [ProfileChangeInfo]? {
        await read("getProfileHistory") {
            guard
                case .ok(let ok) = try await client.getProfileHistory(
                    path: .init(id: project), query: .init(limit: limit))
            else { return nil }
            return try ok.body.json.map(ProfileChangeInfo.init)
        }
    }
}
