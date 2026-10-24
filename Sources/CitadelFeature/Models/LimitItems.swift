import Foundation
import Observation

/// Screen 16 Limits: every scoped setting at this company, its overrides below and recent changes.
@MainActor
@Observable
final class LimitsPage {
    enum Filter: Hashable { case all, setHere, overridden }

    /// Loaded once the screen first opens.
    var isLoaded = false
    /// The company settings section shown (⚙ opens General; "All limits (company) →" opens Limits).
    var section: CompanySettingsSection = .general
    /// Every setting with its server value (the read-only Server column, decision #58).
    var server: [ScopedSetting] = []
    /// Every setting this company may set, with its effective value here.
    var company: [ScopedSetting] = []
    /// The values set below the company, by key: projects, runners, accounts.
    var below: [String: [LimitOverride]] = [:]
    /// The newest sets and resets at this company and the scopes below it.
    var changes: [SettingChangeInfo] = []
    var filter: Filter = .all
    var search = ""
    /// The rest past the main rows ("+ 7 more"), open.
    var showsMore = false
    /// A value refused against its bounds, by key: the row turns red and says the bound (never clamped).
    var refused: [String: String] = [:]
    /// The Devices section's keys and the Audit log's entries; `nil` until the section first opens.
    var devices: [DeviceInfo]?
    var auditLog: [AuditLine]?
    /// The Skills section's versions; `nil` until it first opens.
    var skills: [SkillInfo]?
}

/// Company settings' sections (⚙ next to the switcher): only those the API backs — no members or notifications
/// route exists yet, so neither is listed.
enum CompanySettingsSection: String, CaseIterable, Hashable {
    case general, devices, accounts, limits, skills, audit

    var title: String {
        switch self {
        case .general: "General"
        case .devices: "Devices"
        case .accounts: "Account assignment"
        case .limits: "Limits"
        case .skills: "Skills"
        case .audit: "Audit log"
        }
    }
}

/// A value set below the company: "CIT 10 min", "hetzner-2 80 GB", "claude-work 70%".
struct LimitOverride: Equatable, Sendable {
    /// `project:2`, `runner:3`, `account:4`.
    var scope: String
    /// The project key, runner or account name.
    var owner: String
    var value: String
}

/// One row of the Limits table.
struct LimitRow: Identifiable, Equatable {
    var id: String { setting.key }
    /// The setting at the server: name, bounds, the server value.
    var setting: ScopedSetting
    /// Its value at this company; `nil` when it cannot be set per company.
    var company: ScopedSetting?
    var overrides: [LimitOverride]

    var name: String { LimitNames.name(setting.key) }

    /// Why a setting has no company value: runners and accounts are server-wide / pool-wide (#56, #57).
    var companyNote: String? {
        guard company == nil else { return nil }
        if setting.scopes.contains("runner") { return "runners are server-wide" }
        if setting.scopes.contains("account") { return "accounts are pool-wide" }
        return "server-wide only"
    }
}

/// The settings' names as people read them, and the groups the table shows them in.
enum LimitNames {
    static let names: [String: String] = [
        "run.stall_after_secs": "Stall timeout", "run.token_cap": "Token cap per run",
        "run.stuck_after_secs": "Stuck after", "lease.ttl_secs": "Lease heartbeat",
        "wake.max_attempts": "Wake attempts",
        "breaker.loop_threshold": "Loop breaker", "repair.budget": "Repairs per issue",
        "issue.idle_escalate_secs": "Escalate idle issues after", "runner.disk_cap_bytes": "Disk cap per runner",
        "workspace.idle_secs": "Idle worktree age", "runner.disk_evict_percent": "Evict past",
        "artifact.company_quota_bytes": "Artifact storage quota", "artifact.max_file_bytes": "Largest artifact",
        "budget.warn_percent": "Budget warn", "account.warn_percent": "Account window warn",
        "account.drop_threshold": "Drops before unhealthy", "approval.deadline.pr_merge": "Approval deadline",
        "approval.deadline.sprint_commit": "Approval deadline · sprint",
        "approval.deadline.plan_approval":
            "Approval deadline · plan", "knowledge.budget_bytes": "Knowledge budget",
        "skills.budget_bytes": "Skill budget", "profile.budget_bytes": "Profile budget",
    ]

    /// The groups, in order, and the keys shown before "+ N more".
    static let groups: [(title: String, prefixes: [String])] = [
        ("Runs", ["run.", "lease.", "wake.", "breaker.", "repair.", "issue."]),
        ("Disk & storage", ["runner.disk", "workspace.", "artifact."]),
        ("Cost & usage", ["budget.", "account."]),
        ("Approvals & knowledge", ["approval.", "knowledge.", "skills.", "profile."]),
    ]
    static let main: Set<String> = [
        "run.stall_after_secs", "run.token_cap", "lease.ttl_secs", "runner.disk_cap_bytes", "workspace.idle_secs",
        "artifact.company_quota_bytes", "budget.warn_percent", "account.warn_percent",
        "approval.deadline.pr_merge", "knowledge.budget_bytes", "skills.budget_bytes",
    ]

    /// `run.stall_after_secs` → "Stall timeout"; an unnamed key reads from its last part ("Velocity window").
    static func name(_ key: String) -> String {
        if let name = names[key] { return name }
        let last = key.split(separator: ".").last.map(String.init) ?? key
        let words = last.replacingOccurrences(of: "_secs", with: "").replacingOccurrences(of: "_ms", with: "")
            .replacingOccurrences(of: "_bytes", with: "").replacingOccurrences(of: "_", with: " ")
        return words.prefix(1).uppercased() + words.dropFirst()
    }

    static func group(_ key: String) -> String? {
        groups.first { $0.prefixes.contains { key.hasPrefix($0) } }?.title
    }
}

extension LimitsPage {
    /// Every row, the company's values joined to the server's.
    var rows: [LimitRow] {
        server.map { setting in
            LimitRow(
                setting: setting, company: company.first { $0.key == setting.key }, overrides: below[setting.key] ?? [])
        }
    }

    /// How many values this company sets, and how many are set below it.
    func setHere(_ companyID: Int64) -> Int { company.filter { $0.isSet(at: "company:\(companyID)") }.count }
    var overriddenBelow: Int { below.values.map(\.count).reduce(0, +) }

    /// The rows the filters and the search leave, by group; the rest past the main rows is "more" (shown when
    /// open, filtered or searched).
    func sections(_ companyID: Int64) -> (groups: [(String, [LimitRow])], more: [LimitRow]) {
        let query = search.trimmingCharacters(in: .whitespaces)
        let kept = rows.filter { row in
            switch filter {
            case .all: true
            case .setHere: row.company?.isSet(at: "company:\(companyID)") ?? false
            case .overridden: !row.overrides.isEmpty
            }
        }
        .filter {
            query.isEmpty || $0.name.localizedCaseInsensitiveContains(query)
                || $0.setting.key.localizedCaseInsensitiveContains(query)
        }
        let expanded = showsMore || filter != .all || !query.isEmpty
        var groups: [(String, [LimitRow])] = []
        for group in LimitNames.groups {
            let rows = kept.filter {
                LimitNames.group($0.setting.key) == group.title && (expanded || LimitNames.main.contains($0.id))
            }
            if !rows.isEmpty { groups.append((group.title, rows)) }
        }
        let shown = Set(groups.flatMap { $0.1.map(\.id) })
        return (groups, kept.filter { !shown.contains($0.id) })
    }

    /// Checks a typed value; a refused one is remembered on its row with the bound it broke.
    func check(_ setting: ScopedSetting, _ text: String) -> Bool {
        guard let value = setting.parse(text) else {
            refused[setting.key] = "not a value"
            return false
        }
        if value > setting.max {
            refused[setting.key] = "max \(setting.text(setting.max))"
            return false
        }
        if value < setting.min {
            refused[setting.key] = "min \(setting.text(setting.min))"
            return false
        }
        refused[setting.key] = nil
        return true
    }
}

extension ScopedSetting {
    /// Another value in this setting's unit.
    func text(_ value: Int64) -> String { Self.format(value, unit: unit) }
}
