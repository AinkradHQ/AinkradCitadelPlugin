import CitadelClient
import Foundation
import OpenAPIRuntime

/// Screens 10 and 15: runners and their disk, the account pool, its limits and agents' fallback chains.
extension CitadelServer {
    func runnerList() async -> [RunnerInfo]? {
        await read("listRunners") {
            guard case .ok(let ok) = try await client.listRunners() else { return nil }
            return try ok.body.json.map(RunnerInfo.init)
        }
    }

    func runnerDisk(_ runner: Int64) async -> RunnerDiskInfo? {
        await read("getRunnerDisk") {
            guard case .ok(let ok) = try await client.getRunnerDisk(path: .init(id: runner)) else { return nil }
            return RunnerDiskInfo(try ok.body.json)
        }
    }

    /// The whole pool with each account's use: the admin's, so `nil` for any other device (a 404 in a company).
    func poolUsage() async -> [PoolAccount]? {
        await read("accountUsage") {
            guard case .ok(let ok) = try await scoped(to: nil).client.accountUsage() else { return nil }
            return try ok.body.json.map { PoolAccount($0.account, usage: $0) }
        }
    }

    /// The accounts this company's runs may use, without their use (any device).
    func companyAccounts() async -> [PoolAccount]? {
        await read("listAccounts") {
            guard case .ok(let ok) = try await client.listAccounts() else { return nil }
            return try ok.body.json.map { PoolAccount($0, usage: nil) }
        }
    }

    /// Sets (or replaces) the account's counted limit for that window and unit.
    func setAccountLimit(_ account: Int64, windowSecs: Int64, max: Int64, unit: String) async -> Bool {
        await read("setAccountLimit") {
            let body = Schemas.NewLimit(
                max: max, unit: .init(value1: .init(rawValue: unit), value2: unit), warnPercent: nil,
                windowSecs: windowSecs)
            guard case .ok = try await client.setAccountLimit(path: .init(id: account), body: .json(body)) else {
                return false
            }
            return true
        } ?? false
    }

    /// ↺ on a counted window: removes the limit.
    func clearAccountLimit(_ account: Int64, windowSecs: Int64, unit: String) async -> Bool {
        await read("clearAccountLimit") {
            let path = Operations.ClearAccountLimit.Input.Path(
                id: account, unit: .init(value1: .init(rawValue: unit), value2: unit), windowSecs: windowSecs)
            guard case .ok = try await client.clearAccountLimit(path: path) else { return false }
            return true
        } ?? false
    }

    /// The agent's fallbacks, in order (its own harness and model come before them).
    func fallbacks(agent: Int64) async -> [FallbackEntry]? {
        await read("listFallbacks") {
            guard case .ok(let ok) = try await client.listFallbacks(path: .init(id: agent)) else { return nil }
            return try ok.body.json.map { FallbackEntry(harness: $0.harness.word, model: $0.model) }
        }
    }

    /// Replaces the agent's fallbacks; the chain as the server stored it.
    func setFallbacks(agent: Int64, _ entries: [FallbackEntry]) async -> [FallbackEntry]? {
        await read("setFallbacks") {
            guard
                case .ok(let ok) = try await client.setFallbacks(
                    path: .init(id: agent), body: .json(FallbackEntry.body(entries)))
            else { return nil }
            return try ok.body.json.map { FallbackEntry(harness: $0.harness.word, model: $0.model) }
        }
    }
}
