import AinkradAppKit
import CitadelClient
import Foundation

@testable import CitadelFeature

/// Screens 10 and 15 of the mockups' company: runners and the account pool.
@MainActor
extension CompanyFixture {
    static func setting(
        _ key: String, _ value: Int64, unit: String, min: Int64, max: Int64, source: String? = "server",
        scopes: [String] = ["server", "runner"]
    ) -> ScopedSetting {
        ScopedSetting(
            key: key, description: "", value: value, defaultValue: value, min: min, max: max, unit: unit,
            scopes: scopes, source: source)
    }

    static func runnersPage(_ model: CompanyModel) {
        for issue in [
            IssueInfo(id: 61, key: "CIT-61", title: "Lease heartbeat", projectID: 1, requirementID: 12),
            IssueInfo(id: 63, key: "CIT-63", title: "List + revoke keys", projectID: 1, requirementID: 12),
            IssueInfo(id: 108, key: "AMC-8", title: "Settings pane", projectID: 2, requirementID: nil),
        ] { model.issues[issue.id] = issue }
        model.issues[58] = IssueInfo(
            id: 58, key: "CIT-58", title: "Device registration", projectID: 1, requirementID: 12)
        model.runners = [1: "hetzner-1", 2: "hetzner-2", 3: "ahmed-mbp", 4: "oracle-arm"]
        model.runnersOnline = 2
        model.issueRepos[58] = ["citadel"]
        model.issueRepos[61] = ["citadel", "plugin"]
        model.issueRepos[63] = ["citadel"]
        model.issueRepos[108] = ["mac-client"]
        let page = model.runnersPage
        page.runners = [
            RunnerInfo(
                id: 1, name: "hetzner-1", status: "online", healthReason: nil, lastSeenAt: now.addingTimeInterval(-2),
                tags: ["linux", "docker", "rust"]),
            RunnerInfo(
                id: 2, name: "hetzner-2", status: "unhealthy",
                healthReason:
                    "Claude login expired 2h 10m ago. The runner is up, but its harness probe fails, so the engine stopped sending it Claude work.",
                lastSeenAt: now.addingTimeInterval(-4), tags: ["linux", "docker"]),
            RunnerInfo(
                id: 3, name: "ahmed-mbp", status: "online", healthReason: nil, lastSeenAt: now.addingTimeInterval(-6),
                tags: ["macos", "xcode-27", "swift"]),
            RunnerInfo(
                id: 4, name: "oracle-arm", status: "offline", healthReason: nil,
                lastSeenAt: now.addingTimeInterval(-3 * 86_400 - 600), tags: ["linux", "arm64"]),
        ]
        func worktree(_ issue: Int64, _ gb: Double, active: Bool, idleHours: Double = 0, leftMinutes: Int64? = nil)
            -> WorktreeDiskInfo
        {
            WorktreeDiskInfo(
                issueID: issue, bytes: Int64(gb * 1e9), active: active, idleSecs: Int64(idleHours * 3600),
                removedInSecs: leftMinutes.map { $0 * 60 })
        }
        page.disk = [
            1: RunnerDiskInfo(
                capBytes: 50_000_000_000, used: 31_400_000_000, shared: 19_000_000_000, active: 8_000_000_000,
                idle: 4_400_000_000, evictPercent: 90, full: false, measuredAt: now,
                worktrees: [
                    worktree(42, 3, active: true), worktree(54, 3, active: true), worktree(57, 2, active: true),
                    worktree(61, 3.1, active: false, idleHours: 20.8, leftMinutes: 192),
                    worktree(63, 1.3, active: false, idleHours: 2.3, leftMinutes: 1_300),
                ]),
            2: RunnerDiskInfo(
                capBytes: 80_000_000_000, used: 11_900_000_000, shared: 8_800_000_000, active: 0,
                idle: 3_100_000_000, evictPercent: 90, full: false, measuredAt: now,
                worktrees: [worktree(58, 3.1, active: false, idleHours: 5, leftMinutes: 1_140)]),
            3: RunnerDiskInfo(
                capBytes: 50_000_000_000, used: 43_800_000_000, shared: 31_000_000_000, active: 2_000_000_000,
                idle: 10_800_000_000, evictPercent: 90, full: false, measuredAt: now,
                worktrees: [
                    worktree(9, 2, active: true), worktree(108, 3.2, active: false, idleHours: 9, leftMinutes: 180),
                ]),
        ]
        let cap = setting(
            "runner.disk_cap_bytes", 50_000_000_000, unit: "bytes", min: 5_000_000_000, max: 1_000_000_000_000_000)
        let idle = setting("workspace.idle_secs", 86_400, unit: "seconds", min: 3_600, max: 2_592_000)
        let evict = setting("runner.disk_evict_percent", 90, unit: "percent", min: 50, max: 100)
        page.serverSettings = [cap.key: cap, idle.key: idle, evict.key: evict]
        func overridden(_ setting: ScopedSetting, _ value: Int64, at scope: String) -> ScopedSetting {
            var copy = setting
            copy.value = value
            copy.source = scope
            return copy
        }
        page.settings = [
            1: [cap.key: cap, idle.key: idle, evict.key: evict],
            2: [cap.key: overridden(cap, 80_000_000_000, at: "runner:2"), idle.key: idle, evict.key: evict],
            3: [cap.key: cap, idle.key: overridden(idle, 43_200, at: "runner:3"), evict.key: evict],
            4: [cap.key: cap, idle.key: idle, evict.key: evict],
        ]
        page.isLoaded = true
    }

    static func accountsPage(_ model: CompanyModel) {
        let page = model.accountsPage
        func window(_ name: String, _ used: Double, resetsIn hours: Double) -> SignalWindow {
            SignalWindow(name: name, utilization: used, resetsAt: now.addingTimeInterval(hours * 3600))
        }
        func account(
            _ id: Int64, _ label: String, harness: String = "claude", billing: String = "subscription",
            status: String = "active", drops: Int64 = 0, tokens: [Int64: Int64], windows: [SignalWindow] = [],
            limits: [AccountLimitInfo] = []
        ) -> PoolAccount {
            PoolAccount(
                id: id, label: label, harness: harness, billing: billing, status: status, statusReason: nil,
                statusUntil: nil, configDir: "~/.citadel/acct/\(label)", companyIDs: tokens.keys.sorted(), drops: drops,
                companyTokens: tokens, signalWindows: windows, limits: limits,
                planTier: billing == "subscription" ? (harness == "codex" ? "Pro" : "Max 20×") : nil,
                recentDrops: drops, recentDropsWindowSecs: 86_400)
        }
        var work = account(
            2, "claude-work", status: "limited", tokens: [1: 400, 2: 600],
            windows: [window("five_hour", 1.0, resetsIn: 1.1), window("seven_day", 0.63, resetsIn: 90)])
        work.planTier = "Max 5×"
        work.statusReason = "the harness reports the plan limit reached"
        work.statusUntil = now.addingTimeInterval(1.1 * 3600)
        page.accounts = [
            account(
                1, "claude-personal", tokens: [1: 820, 3: 180],
                windows: [window("five_hour", 0.71, resetsIn: 2.3), window("seven_day", 0.48, resetsIn: 90)]),
            work,
            account(
                3, "claude-max-3", drops: 2, tokens: [1: 1_000],
                windows: [window("five_hour", 0.22, resetsIn: 3.6), window("seven_day", 0.31, resetsIn: 90)]),
            account(
                4, "codex-pro", harness: "codex", tokens: [1: 700, 2: 300],
                limits: [
                    AccountLimitInfo(
                        windowSecs: 18_000, unit: "tokens", max: 3_000_000, warnPercent: 80, used: 2_580_000),
                    AccountLimitInfo(
                        windowSecs: 604_800, unit: "tokens", max: 20_000_000, warnPercent: 80, used: 11_000_000),
                ]),
            account(5, "anthropic-api", billing: "metered", tokens: [1: 0, 2: 0]),
        ]
        let warn = setting(
            "account.warn_percent", 80, unit: "percent", min: 1, max: 100, scopes: ["server", "account"])
        let drops = setting(
            "account.drop_threshold", 3, unit: "count", min: 1, max: 100, scopes: ["server", "account"])
        let window = setting(
            "account.drop_window_secs", 600, unit: "seconds", min: 60, max: 86_400, scopes: ["server", "account"])
        let unhealthy = setting(
            "account.unhealthy_secs", 600, unit: "seconds", min: 60, max: 604_800, scopes: ["server", "account"])
        page.serverSettings = [warn.key: warn, drops.key: drops, window.key: window, unhealthy.key: unhealthy]
        for id in page.accounts.map(\.id) { page.settings[id] = page.serverSettings }
        var workWarn = warn
        workWarn.value = 70
        workWarn.source = "account:2"
        page.settings[2]?[warn.key] = workWarn
        page.pickedAccount = 4
        page.chainAgent = 4
        page.chain = [
            FallbackEntry(harness: "codex", model: "gpt-5.5", isOwn: true),
            FallbackEntry(harness: "claude", model: "opus-5.5"),
            FallbackEntry(harness: "claude", model: "sonnet-5"),
            FallbackEntry(harness: "opencode", model: "qwen3-coder"),
        ]
        page.canSeeWholePool = true
        page.isLoaded = true
        model.issues[65] = IssueInfo(id: 65, key: "CIT-65", title: "Rate-limit soak", projectID: 1, requirementID: 12)
        var moved = run(429, agent: 4, issue: 65, minutes: 30, tokens: 40_000, harness: "claude", model: "opus-5.5")
        moved.state = "succeeded"
        model.runs[429] = moved
    }

    /// The `run.fallback` event the Last fallbacks tile reads off the stream.
    static func fallbackEvent(seq: Int64, run: Int64, from: String, to: String, reason: String) throws
        -> Components.Schemas.Event
    {
        let json =
            #"{"seq":\#(seq),"at":"2026-10-23T11:40:00.000Z","payload":{"type":"audit","audit_seq":\#(seq),"action":"run.fallback","actor":{"kind":"system"},"run_id":\#(run),"entity_kind":"run","entity_id":\#(run),"details":{"from":{"model":"\#(from)"},"to":{"model":"\#(to)"},"reason":"\#(reason)"}}}"#
        guard let event = try EventFrame.decode(Data(json.utf8)).event else {
            throw CocoaError(.coderReadCorrupt)
        }
        return event
    }
}
