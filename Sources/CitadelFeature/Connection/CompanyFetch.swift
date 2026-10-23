import CitadelClient
import Foundation
import OpenAPIRuntime

/// The reads the screens need, each mapped to the plain values in `CompanyInfo.swift`. A read that fails returns
/// `nil` (logged) so one missing endpoint or a 403 never blanks a whole screen.
extension CitadelServer {
    func orgChart(company: Int64) async -> ([AgentInfo], [DepartmentInfo])? {
        await read("getOrgChart") {
            guard case .ok(let ok) = try await client.getOrgChart(path: .init(id: company)) else { return nil }
            let chart = try ok.body.json
            return (chart.agents.map(AgentInfo.init), chart.departments.map(DepartmentInfo.init))
        }
    }

    func agent(_ id: Int64) async -> AgentInfo? {
        await read("getAgent") {
            guard case .ok(let ok) = try await client.getAgent(path: .init(id: id)) else { return nil }
            return AgentInfo(try ok.body.json)
        }
    }

    func avatar(agent id: Int64) async -> Data? {
        await read("getAvatar") {
            guard case .ok(let ok) = try await client.getAvatar(path: .init(id: id)) else { return nil }
            let body: HTTPBody =
                switch ok.body {
                case .jpeg(let b), .png(let b), .imageWebp(let b): b
                }
            return try await Data(collecting: body, upTo: 4 << 20)
        }
    }

    func agentRuns(_ agent: Int64, limit: Int32) async -> [RunInfo]? {
        await read("listAgentRuns") {
            guard case .ok(let ok) = try await client.listAgentRuns(path: .init(id: agent), query: .init(limit: limit))
            else { return nil }
            return try ok.body.json.items.map(RunInfo.init)
        }
    }

    func run(_ id: Int64) async -> RunInfo? {
        await read("getRun") {
            guard case .ok(let ok) = try await client.getRun(path: .init(id: id)) else { return nil }
            return RunInfo(try ok.body.json)
        }
    }

    func issue(_ id: Int64) async -> IssueInfo? {
        await read("getIssue") {
            guard case .ok(let ok) = try await client.getIssue(path: .init(id: id)) else { return nil }
            return IssueInfo(try ok.body.json)
        }
    }

    func issueRepos(_ id: Int64) async -> [String]? {
        await read("getIssueRepos") {
            guard case .ok(let ok) = try await client.getIssueRepos(path: .init(id: id)) else { return nil }
            return try ok.body.json.repos
        }
    }

    /// Every chunk of a run's transcript, page by page.
    func transcript(run: Int64) async -> [TranscriptChunkInfo]? {
        var chunks: [TranscriptChunkInfo] = []
        var after: Int64?
        repeat {
            let page: Schemas.PageTranscriptChunk? = await read("getTranscript") {
                guard
                    case .ok(let ok) = try await client.getTranscript(
                        path: .init(id: run), query: .init(after: after, limit: 500))
                else { return nil }
                return try ok.body.json
            }
            guard let page else { return chunks.isEmpty ? nil : chunks }
            chunks += page.items.map(TranscriptChunkInfo.init)
            after = page.nextAfter
        } while after != nil
        return chunks
    }

    func approvals(company: Int64) async -> [ApprovalInfo]? {
        await read("listApprovals") {
            guard
                case .ok(let ok) = try await client.listApprovals(path: .init(id: company), query: .init(pending: true))
            else { return nil }
            return try ok.body.json.map(ApprovalInfo.init)
        }
    }

    func stuck() async -> [StuckInfo]? {
        await read("listStuck") {
            guard case .ok(let ok) = try await client.listStuck() else { return nil }
            return try ok.body.json.map(StuckInfo.init)
        }
    }

    func costs(company: Int64) async -> (SpendInfo, [Schemas.BudgetStanding])? {
        await read("getCompanyCosts") {
            guard case .ok(let ok) = try await client.getCompanyCosts(path: .init(id: company)) else { return nil }
            let costs = try ok.body.json
            return (SpendInfo(costs.report), costs.budgets)
        }
    }

    /// Open requirements with their progress by points.
    func requirements() async -> [RequirementInfo]? {
        let all: [Schemas.Requirement]? = await read("listRequirements") {
            guard case .ok(let ok) = try await client.listRequirements() else { return nil }
            return try ok.body.json
        }
        guard let all else { return nil }
        var out: [RequirementInfo] = []
        for requirement in all where !["done", "cancelled"].contains(requirement.state.word) {
            let tree: Schemas.RequirementTree? = await read("getRequirementTree") {
                guard case .ok(let ok) = try await client.getRequirementTree(path: .init(id: requirement.id))
                else { return nil }
                return try ok.body.json
            }
            out.append(RequirementInfo(requirement, tree: tree))
        }
        return out
    }

    func projects(company: Int64) async -> [ProjectInfo]? {
        await read("listProjects") {
            guard case .ok(let ok) = try await client.listProjects(path: .init(id: company)) else { return nil }
            return try ok.body.json.map {
                ProjectInfo(id: $0.id, key: $0.key, name: $0.name, teamID: $0.teamId, mode: $0.mode.word)
            }
        }
    }

    /// The company's active sprint and its points.
    func activeSprint(company: Int64) async -> SprintInfo? {
        let projects: [Schemas.Project]? = await read("listProjects") {
            guard case .ok(let ok) = try await client.listProjects(path: .init(id: company)) else { return nil }
            return try ok.body.json
        }
        for project in projects ?? [] {
            let sprints: [Schemas.Sprint]? = await read("listSprints") {
                guard case .ok(let ok) = try await client.listSprints(path: .init(id: project.id)) else { return nil }
                return try ok.body.json
            }
            guard let sprint = sprints?.first(where: { $0.state.word == "active" }) else { continue }
            let report: Schemas.SprintReport? = await read("getSprintReport") {
                guard case .ok(let ok) = try await client.getSprintReport(path: .init(id: sprint.id)) else {
                    return nil
                }
                return try ok.body.json
            }
            return SprintInfo(
                id: sprint.id, name: sprint.name, projectKey: project.key, startsOn: sprint.startsOn.flatMap(Self.day),
                endsOn: sprint.endsOn.flatMap(Self.day), committed: Int(report?.committed ?? 0),
                completed: Int(report?.completed ?? 0))
        }
        return nil
    }

    /// The accounts this company's runs use, with their fullest window.
    func accounts(company: Int64) async -> [AccountInfo]? {
        let accounts: [Schemas.Account]? = await read("listAccounts") {
            guard case .ok(let ok) = try await client.listAccounts() else { return nil }
            return try ok.body.json
        }
        guard let accounts else { return nil }
        let usage: [Schemas.AccountUsage] =
            await read("accountUsage") {
                guard case .ok(let ok) = try await client.accountUsage() else { return nil }
                return try ok.body.json
            } ?? []
        return accounts.filter { $0.companyIds.contains(company) }.map { account in
            AccountInfo(account, usage: usage.first { $0.account.id == account.id })
        }
    }

    func runners() async -> [Int64: String]? {
        await read("listRunners") {
            guard case .ok(let ok) = try await client.listRunners() else { return nil }
            return Dictionary(uniqueKeysWithValues: try ok.body.json.map { ($0.id, $0.name) })
        }
    }

    /// A scoped setting's effective value at `scope` (`company:1`, `project:2`).
    func setting(scope: String, key: String) async -> LimitSetting? {
        await read("getSetting") {
            guard case .ok(let ok) = try await client.getSetting(path: .init(scope: scope, key: key)) else {
                return nil
            }
            let setting = try ok.body.json
            return LimitSetting(value: setting.value, source: setting.source)
        }
    }

    /// Approve or deny; `raiseTokens` approves a budget overrun with that many more tokens.
    func decide(approval: Int64, approve: Bool, raiseTokens: Int64? = nil) async -> Bool {
        await read("decideApproval") {
            guard
                case .ok = try await client.decideApproval(
                    path: .init(id: approval), body: .json(.init(approve: approve, raiseTokens: raiseTokens)))
            else { return false }
            return true
        } ?? false
    }

    private static func day(_ text: String) -> Date? {
        try? Date(text, strategy: Date.ISO8601FormatStyle().year().month().day())
    }

    private func read<T>(_ operation: String, _ work: () async throws -> T?) async -> T? {
        do {
            return try await work()
        } catch {
            Log.connection.error(
                "\(operation, privacy: .public) failed: \(String(describing: error), privacy: .public)")
            return nil
        }
    }
}
