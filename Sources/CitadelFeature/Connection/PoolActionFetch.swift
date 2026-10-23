import CitadelClient
import Foundation

/// Screens 10 and 15's writes and the runs list: wake a runner, add an account, the company's recent runs.
extension CitadelServer {
    /// "Wake now" (`now`: pushed to the Mac at once) or "Run when I'm back" (`when_back`: its work waits); the runner
    /// with its wake request, or the server's refusal.
    func wake(runner: Int64, when: String) async -> Result<RunnerInfo, ServerAnswer> {
        do {
            switch try await client.wakeRunner(path: .init(id: runner), body: .json(.init(when: when))) {
            case .ok(let ok): return .success(RunnerInfo(try ok.body.json))
            case .badRequest(let r): return .failure(.refusal(400, try? r.body.json))
            case .unauthorized: return .failure(.refusal(401, nil))
            case .forbidden(let r): return .failure(.refusal(403, try? r.body.json))
            case .notFound(let r): return .failure(.refusal(404, try? r.body.json))
            case .conflict(let r): return .failure(.refusal(409, try? r.body.json))
            case .tooManyRequests: return .failure(.refusal(429, nil))
            case .internalServerError(let r): return .failure(.refusal(500, try? r.body.json))
            case .undocumented(let status, _): return .failure(.refusal(status, nil))
            }
        } catch {
            return .failure(ServerAnswer(status: 0, code: "unreachable", message: error.localizedDescription))
        }
    }

    /// "+ Add runner": a new runner and its key, which the server shows only now.
    func registerRunner(name: String, tags: [String]) async -> Result<RegisteredRunnerInfo, ServerAnswer> {
        await attempt({
            try await scoped(to: nil).client.registerRunner(body: .json(.init(name: name, tags: tags)))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            let body = try ok.body.json
            return RegisteredRunnerInfo(runner: RunnerInfo(body.runner), key: body.key)
        }
    }

    /// Drain (no new run; its runs finish) or undrain; the runner after.
    func drain(runner: Int64, _ drained: Bool) async -> Result<RunnerInfo, ServerAnswer> {
        let client = scoped(to: nil).client
        if drained {
            return await attempt({ try await client.drainRunner(path: .init(id: runner)) }) {
                guard case .ok(let ok) = $0 else { return nil }
                return RunnerInfo(try ok.body.json)
            }
        }
        return await attempt({ try await client.undrainRunner(path: .init(id: runner)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return RunnerInfo(try ok.body.json)
        }
    }

    /// "Keep awake while jobs queue" (Power Nap on the Mac); the runner after.
    func setPowerNap(runner: Int64, _ enabled: Bool) async -> Result<RunnerInfo, ServerAnswer> {
        await attempt({
            try await scoped(to: nil).client.setRunnerPowerNap(
                path: .init(id: runner), body: .json(.init(enabled: enabled)))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            return RunnerInfo(try ok.body.json)
        }
    }

    /// "Remove runner…": its key stops working.
    func removeRunner(_ runner: Int64) async -> ServerAnswer? {
        await act { try await scoped(to: nil).client.removeRunner(path: .init(id: runner)) }
    }

    /// The end of the runner's own log, redacted by the runner and the server.
    func runnerLog(_ runner: Int64, limit: Int32 = 200) async -> Result<[String], ServerAnswer> {
        await attempt({
            try await scoped(to: nil).client.getRunnerLogs(path: .init(id: runner), query: .init(limit: limit))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            return try ok.body.json.lines
        }
    }

    /// Adds an account to the pool (active, assigned to no company yet).
    func createAccount(_ draft: NewAccountDraft) async -> Result<PoolAccount, ServerAnswer> {
        do {
            switch try await scoped(to: nil).client.createAccount(body: .json(draft.body)) {
            case .ok(let ok): return .success(PoolAccount(try ok.body.json, usage: nil))
            case .badRequest(let r): return .failure(.refusal(400, try? r.body.json))
            case .unauthorized: return .failure(.refusal(401, nil))
            case .forbidden(let r): return .failure(.refusal(403, try? r.body.json))
            case .notFound(let r): return .failure(.refusal(404, try? r.body.json))
            case .conflict(let r): return .failure(.refusal(409, try? r.body.json))
            case .tooManyRequests: return .failure(.refusal(429, nil))
            case .internalServerError(let r): return .failure(.refusal(500, try? r.body.json))
            case .undocumented(let status, _): return .failure(.refusal(status, nil))
            }
        } catch {
            return .failure(ServerAnswer(status: 0, code: "unreachable", message: error.localizedDescription))
        }
    }

    /// Names (or clears, `nil`) the account's plan tier; the tier as stored.
    func setPlanTier(account: Int64, _ tier: String?) async -> Result<String?, ServerAnswer> {
        await attempt({
            try await scoped(to: nil).client.setAccountPlan(
                path: .init(id: account), body: .json(.init(planTier: tier)))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            return .some(try ok.body.json.planTier)
        }
    }

    /// The company's newest runs, newest first.
    func companyRuns(company: Int64, limit: Int32) async -> [RunInfo]? {
        await read("listCompanyRuns") {
            guard
                case .ok(let ok) = try await client.listCompanyRuns(
                    path: .init(id: company), query: .init(limit: limit))
            else { return nil }
            return try ok.body.json.items.map(RunInfo.init)
        }
    }
}

extension ServerAnswer {
    /// A refusal as the server worded it (`ErrorBody`), or just its status.
    static func refusal(_ status: Int, _ body: Schemas.ErrorBody?) -> ServerAnswer {
        ServerAnswer(status: status, code: body?.code ?? "", message: body?.message ?? "", errorID: body?.errorId)
    }
}
