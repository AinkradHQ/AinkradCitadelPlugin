import AinkradAppKit
import Foundation

@testable import CitadelFeature

/// The prototype's Accounts (`accounts.js` POOL_ACCOUNTS): the pool with a limited, a flaky and a logged-out
/// account, the runners' logins, the company's fallback triggers and agents sharing chains.
@MainActor
extension CompanyFixture {
    static func accountsParityPage(_ model: CompanyModel) {
        let page = model.accountsPage
        func window(_ name: String, _ used: Double, resetsIn hours: Double) -> SignalWindow {
            SignalWindow(name: name, utilization: used, resetsAt: now.addingTimeInterval(hours * 3600))
        }
        func account(
            _ id: Int64, _ label: String, harness: String = "claude", billing: String = "subscription",
            status: String = "active", plan: String? = nil, drops: Int64 = 0, tokens: [Int64: Int64],
            windows: [SignalWindow] = [], limits: [AccountLimitInfo] = []
        ) -> PoolAccount {
            PoolAccount(
                id: id, label: label, harness: harness, billing: billing, status: status, statusReason: nil,
                statusUntil: nil, configDir: "~/.citadel/acct/\(label)", companyIDs: tokens.keys.sorted(), drops: drops,
                companyTokens: tokens, signalWindows: windows, limits: limits, planTier: plan, recentDrops: drops,
                recentDropsWindowSecs: 86_400)
        }
        var work = account(
            2, "claude-work", status: "limited", plan: "Max 5×", tokens: [1: 400, 2: 600],
            windows: [window("five_hour", 1.0, resetsIn: 1.1), window("seven_day", 0.63, resetsIn: 90)])
        work.statusUntil = now.addingTimeInterval(1.1 * 3600)
        page.accounts = [
            account(
                1, "claude-personal", plan: "Max 20×", tokens: [1: 820, 3: 180],
                windows: [window("five_hour", 0.71, resetsIn: 2.3), window("seven_day", 0.48, resetsIn: 90)]),
            work,
            account(
                3, "claude-max-3", plan: "Max 20×", drops: 4, tokens: [1: 1_000],
                windows: [window("five_hour", 0.22, resetsIn: 3.6), window("seven_day", 0.31, resetsIn: 90)]),
            account(
                4, "codex-pro", harness: "codex", plan: "Pro", tokens: [1: 700, 2: 300],
                limits: [
                    AccountLimitInfo(
                        windowSecs: 18_000, unit: "tokens", max: 3_000_000, warnPercent: 80, used: 2_580_000),
                    AccountLimitInfo(
                        windowSecs: 604_800, unit: "tokens", max: 20_000_000, warnPercent: 80, used: 11_000_000),
                ]),
            account(5, "opencode-local", harness: "opencode", billing: "metered", tokens: [1: 2_100]),
            account(6, "anthropic-api", billing: "metered", tokens: [1: 0, 2: 0]),
            account(
                7, "codex-team", harness: "codex", plan: "Team", tokens: [2: 900],
                windows: [window("five_hour", 0.44, resetsIn: 1.5), window("seven_day", 0.61, resetsIn: 48)]),
        ]
        func login(_ dir: String, _ harness: String, _ state: String = "logged_in", _ ids: [Int64]) -> RunnerLoginInfo {
            RunnerLoginInfo(dir: dir, harness: harness, state: state, accountIDs: ids)
        }
        page.runners = [
            RunnerInfo(
                id: 1, name: "hetzner-1", status: "online", healthReason: nil, lastSeenAt: now, tags: ["linux"],
                logins: [
                    login("accounts/claude-personal", "claude", "logged_in", [1, 2, 3]),
                    login("accounts/opencode-local", "opencode", "logged_in", [5]),
                ]),
            RunnerInfo(
                id: 2, name: "hetzner-2", status: "online", healthReason: nil, lastSeenAt: now, tags: ["linux"],
                logins: [
                    login("accounts/claude-personal", "claude", "logged_in", [1, 2, 3]),
                    login("accounts/opencode-local", "opencode", "logged_out", [5]),
                ]),
            RunnerInfo(
                id: 4, name: "oracle-arm", status: "online", healthReason: nil, lastSeenAt: now, tags: ["arm64"],
                logins: [login("accounts/opencode-local", "opencode", "logged_in", [5])]),
        ]
        let warn = setting(
            "account.warn_percent", 80, unit: "percent", min: 1, max: 100, scopes: ["server", "account"])
        let drops = setting(
            "account.drop_threshold", 5, unit: "count", min: 1, max: 100, scopes: ["server", "account"])
        let window = setting(
            "account.drop_window_secs", 3_600, unit: "seconds", min: 60, max: 86_400, scopes: ["server", "account"])
        page.serverSettings = [warn.key: warn, drops.key: drops, window.key: window]
        for id in page.accounts.map(\.id) { page.settings[id] = page.serverSettings }
        var workWarn = warn
        workWarn.value = 70
        workWarn.source = "account:2"
        page.settings[2]?[warn.key] = workWarn
        page.companySettings = Dictionary(
            uniqueKeysWithValues: AccountsPage.triggers.map {
                (
                    $0.key,
                    setting($0.key, 1, unit: "count", min: 0, max: 1, source: "server", scopes: ["server", "company"])
                )
            })
        page.companySettings["fallback.on_unhealthy"]?.value = 0
        page.companySettings["account.at_limit"] = setting(
            "account.at_limit", 0, unit: "count", min: 0, max: 1, scopes: ["server", "company"])
        let claudeFirst = [
            FallbackEntry(harness: "claude", model: "opus-5.5"), FallbackEntry(harness: "codex", model: "gpt-5.5"),
            FallbackEntry(harness: "claude", model: "sonnet-5"),
        ]
        for agent in model.agents.values {
            switch (agent.harness, agent.model) {
            case ("claude", "sonnet-5"): page.agentFallbacks[agent.id] = Array(claudeFirst.prefix(2))
            case ("claude", "opus-5.5"): page.agentFallbacks[agent.id] = Array(claudeFirst.dropFirst())
            default:
                page.agentFallbacks[agent.id] = [claudeFirst[0], FallbackEntry(harness: "opencode", model: "qwen3")]
            }
        }
        page.chainAgent = 4
        page.chain =
            [FallbackEntry(harness: "codex", model: "gpt-5.5", isOwn: true)] + (page.agentFallbacks[4] ?? [])
        page.pickedAccount = 4
        page.canSeeWholePool = true
        page.isLoaded = true
        for (run, account) in [(Int64(418), Int64(4)), (421, 1), (419, 1), (430, 3)] {
            model.runs[run]?.accountID = account
        }
        model.issues[65] = IssueInfo(id: 65, key: "CIT-65", title: "Rate-limit soak", projectID: 1, requirementID: 12)
        var moved = run(429, agent: 4, issue: 65, minutes: 30, tokens: 40_000, harness: "claude", model: "opus-5.5")
        moved.state = "succeeded"
        model.runs[429] = moved
    }
}
