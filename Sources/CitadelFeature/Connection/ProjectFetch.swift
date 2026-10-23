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
    func orderRepos(project: Int64, names: [String]) async -> Result<[RepoInfo], RepoRefusal> {
        await repoWrite("orderRepos") {
            switch try await client.orderRepos(path: .init(id: project), body: .json(.init(repos: names))) {
            case .ok(let ok): .success(try ok.body.json.map(RepoInfo.init))
            case .badRequest(let bad): .failure(RepoRefusal(message: try bad.body.json.message))
            default: .failure(RepoRefusal(message: "The server did not take the new order."))
            }
        }
    }

    /// ★: makes `repo` the project's primary (the default for new issues).
    func setPrimary(repo: Int64) async -> Result<[RepoInfo], RepoRefusal> {
        await repoWrite("setPrimaryRepo") {
            switch try await client.setPrimaryRepo(path: .init(id: repo)) {
            case .ok(let ok): .success(try ok.body.json.map(RepoInfo.init))
            case .badRequest(let bad): .failure(RepoRefusal(message: try bad.body.json.message))
            default: .failure(RepoRefusal(message: "The server did not change the primary repo."))
            }
        }
    }

    /// ✕: refused (400, with the server's reason) while an open issue touches it, or for the primary while there
    /// are others. The repos left.
    func removeRepo(_ repo: Int64) async -> Result<[RepoInfo], RepoRefusal> {
        await repoWrite("removeRepo") {
            switch try await client.removeRepo(path: .init(id: repo)) {
            case .ok(let ok): .success(try ok.body.json.map(RepoInfo.init))
            case .badRequest(let bad): .failure(RepoRefusal(message: try bad.body.json.message))
            default: .failure(RepoRefusal(message: "The server did not remove the repo."))
            }
        }
    }

    /// "＋ Add repository": the server checks the URL and the token reference before it saves.
    func addRepo(project: Int64, _ body: Schemas.RepoBody) async -> Result<RepoInfo, RepoRefusal> {
        await repoWrite("addRepo") {
            switch try await client.addRepo(path: .init(id: project), body: .json(body)) {
            case .ok(let ok): .success(RepoInfo(try ok.body.json))
            case .badRequest(let bad): .failure(RepoRefusal(message: try bad.body.json.message))
            default: .failure(RepoRefusal(message: "The server did not add the repo."))
            }
        }
    }

    private func repoWrite<T>(
        _ operation: String, _ work: () async throws -> Result<T, RepoRefusal>
    ) async -> Result<T, RepoRefusal> {
        await read(operation, work) ?? .failure(RepoRefusal(message: "Couldn't reach the server."))
    }
}

/// Why the server refused a repo change, in its words.
struct RepoRefusal: Error, Equatable {
    var message: String
}
