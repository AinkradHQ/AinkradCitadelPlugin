import AinkradAppKit
import Foundation

/// Accounts (prototype `accounts.js`): what the screen derives from the pool, the runners' logins and the agents'
/// chains — health consistent with Runners, headroom per harness, the chains agents share, warn crossings.
extension AccountsPage {
    /// The runners where the account's login is logged out (`Runner.logins[].account_ids`).
    func loggedOutRunners(_ account: PoolAccount) -> [RunnerInfo] {
        runners.filter { runner in
            runner.logins.contains { $0.state == "logged_out" && $0.accountIDs.contains(account.id) }
        }
    }

    /// Every runner that reports a login for the account, with that login: the Re-login drawer's tiles.
    func logins(of account: PoolAccount) -> [(runner: RunnerInfo, login: RunnerLoginInfo)] {
        runners.compactMap { runner in
            runner.logins.first { $0.accountIDs.contains(account.id) }.map { (runner, $0) }
        }
    }

    /// The account's health as Runners sees it too: a working account logged out on a runner is "partial".
    func health(of account: PoolAccount) -> PoolAccount.Health {
        let base = account.health
        guard base == .healthy || base == .flaky, !loggedOutRunners(account).isEmpty else { return base }
        return .partial
    }

    /// The `fallback.on_*` triggers the server falls back on, in the chips' order, with their company values.
    static let triggers: [(key: String, title: String)] = [
        ("fallback.on_rate_limited", "rate-limited"), ("fallback.on_quota", "out of quota"),
        ("fallback.on_model_unavailable", "model unavailable"), ("fallback.on_unhealthy", "account unhealthy"),
    ]

    /// An agent's whole chain: its own (harness, model), then its fallbacks.
    func chain(of agent: AgentInfo) -> [FallbackEntry] {
        [FallbackEntry(harness: agent.harness, model: agent.model, isOwn: true)] + (agentFallbacks[agent.id] ?? [])
    }

    /// The chains agents share (identical own entry and fallbacks): Presets until the server stores named presets.
    func sharedChains(_ agents: [AgentInfo]) -> [SharedChain] {
        var groups: [String: SharedChain] = [:]
        for agent in agents where agentFallbacks[agent.id] != nil {
            let entries = chain(of: agent)
            let key = entries.map(\.id).joined(separator: ">")
            groups[key, default: SharedChain(id: key, entries: entries, agents: [])].agents.append(agent.id)
        }
        var named: [String: Int] = [:]
        return groups.values.filter { $0.agents.count > 1 }
            .sorted { ($0.agents.count, $1.id) > ($1.agents.count, $0.id) }
            .map { chain in
                var chain = chain
                let base = "\(AgentLook.harnessName(chain.entries.first?.harness ?? "")) first"
                named[base, default: 0] += 1
                chain.name = named[base] == 1 ? base : "\(chain.entries.first?.model ?? base) first"
                return chain
            }
    }
}

/// A chain several agents run on: the shared "preset" (derived — named presets need the server).
struct SharedChain: Identifiable, Equatable {
    let id: String
    var entries: [FallbackEntry]
    var agents: [Int64]
    var name = ""

    var harness: String { entries.first?.harness ?? "" }
    /// "gpt-5.5 → opus-5.5 → qwen3-coder".
    var detail: String { entries.map(\.model).joined(separator: " → ") }
}

extension PoolAccount.Health {
    /// The pill's word.
    var word: String {
        switch self {
        case .disabled: "paused"
        case .partial: "logged out on 1 runner"
        default: rawValue
        }
    }

    /// Its colour as the prototype's `AC_HC` (healthy green, at limit amber, partial orange, flaky red, paused slate).
    var tone: AinkradChartTone {
        switch self {
        case .healthy: .success
        case .atLimit, .partial: .warning
        case .flaky, .unhealthy: .danger
        case .disabled: .muted
        }
    }

    /// The overview legend's order and words.
    static let legend: [(PoolAccount.Health, String)] = [
        (.healthy, "Healthy"), (.atLimit, "At limit"), (.partial, "Logged out on a runner"), (.flaky, "Flaky"),
        (.unhealthy, "Unhealthy"), (.disabled, "Paused"),
    ]
}

/// One harness's headroom in its current window: the mean of its accounts' first windows left, or metered.
struct Headroom: Identifiable, Equatable {
    var id: String { harness }
    let harness: String
    let accounts: Int
    /// 0…1 used, nil when no account reports a window (metered).
    let used: Double?

    static func of(_ accounts: [PoolAccount], warnPercent: (Int64) -> Int) -> [Headroom] {
        var order: [String] = []
        for account in accounts where !order.contains(account.harness) { order.append(account.harness) }
        return order.map { harness in
            let mine = accounts.filter { $0.harness == harness }
            let firsts = mine.filter { $0.status != "disabled" }
                .compactMap { $0.windows(warnPercent: warnPercent($0.id)).first?.fraction }
            let used = firsts.isEmpty ? nil : firsts.map { min($0, 1) }.reduce(0, +) / Double(firsts.count)
            return Headroom(harness: harness, accounts: mine.count, used: used)
        }
    }
}

/// A window that passed its warn mark between two reads: "claude-personal passed 80% of its 5 h window".
struct WarnCrossing: Equatable {
    let account: String
    let window: String
    let percent: Int
    let reset: String?

    static func between(old: [PoolAccount], new: [PoolAccount], warnPercent: (Int64) -> Int) -> [WarnCrossing] {
        new.flatMap { account -> [WarnCrossing] in
            guard let before = old.first(where: { $0.id == account.id }) else { return [] }
            let warn = warnPercent(account.id)
            let was = Dictionary(
                before.windows(warnPercent: warn).map { ($0.id, $0.fraction) }, uniquingKeysWith: { a, _ in a })
            return account.windows(warnPercent: warn).compactMap { window in
                guard let prior = was[window.id], prior < window.warnFraction, window.isPastWarn, !window.isAtLimit
                else { return nil }
                return WarnCrossing(
                    account: account.label, window: window.label, percent: warn,
                    reset: window.resetText(now: Date()))
            }
        }
    }
}
