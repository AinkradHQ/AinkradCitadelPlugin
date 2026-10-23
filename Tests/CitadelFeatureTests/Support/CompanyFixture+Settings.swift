import Foundation

@testable import CitadelFeature

/// Screens 14 and 16 as the mockups draw them (Designs/citadel/14-project-settings, 16-limits).
@MainActor
extension CompanyFixture {
    static func setting(
        _ key: String, _ value: Int64, unit: String, _ min: Int64, _ max: Int64, scopes: [String],
        source: String? = nil, defaultValue: Int64? = nil
    ) -> ScopedSetting {
        ScopedSetting(
            key: key, description: "", value: value, defaultValue: defaultValue ?? value, min: min, max: max,
            unit: unit, scopes: scopes, source: source)
    }

    static let scp = ["server", "company", "project"]

    /// Every setting at the server.
    static var serverSettings: [ScopedSetting] {
        [
            setting("run.stall_after_secs", 900, unit: "seconds", 60, 7_200, scopes: scp),
            setting("run.token_cap", 150_000, unit: "tokens", 10_000, 2_000_000, scopes: scp),
            setting("run.stuck_after_secs", 1_800, unit: "seconds", 60, 86_400, scopes: scp),
            setting("lease.ttl_secs", 10, unit: "seconds", 5, 120, scopes: ["server", "runner"]),
            setting(
                "runner.disk_cap_bytes", 50_000_000_000, unit: "bytes", 5_000_000_000, 1_000_000_000_000,
                scopes: ["server", "runner"]),
            setting("workspace.idle_secs", 86_400, unit: "seconds", 3_600, 2_592_000, scopes: ["server", "runner"]),
            setting(
                "artifact.company_quota_bytes", 20_000_000_000, unit: "bytes", 1_000_000_000, 500_000_000_000,
                scopes: ["server", "company"]),
            setting("budget.warn_percent", 80, unit: "percent", 50, 99, scopes: ["server", "company"]),
            setting("account.warn_percent", 80, unit: "percent", 50, 99, scopes: ["server", "account"]),
            setting(
                "approval.deadline.pr_merge", 86_400, unit: "seconds", 3_600, 604_800, scopes: ["server", "company"]),
            setting("knowledge.budget_bytes", 4_000, unit: "bytes", 0, 32_000, scopes: scp),
            setting("skills.budget_bytes", 8_000, unit: "bytes", 0, 32_000, scopes: scp),
            setting("profile.budget_bytes", 4_000, unit: "bytes", 1_000, 16_000, scopes: scp),
            setting("repair.budget", 3, unit: "count", 0, 50, scopes: scp),
            setting("routing.small_max_points", 2, unit: "count", 0, 100, scopes: scp),
            setting("account.drop_threshold", 3, unit: "count", 1, 100, scopes: ["server", "account"]),
            setting("runner.disk_evict_percent", 90, unit: "percent", 50, 100, scopes: ["server", "runner"]),
            setting("dispatch.fallback_poll_ms", 5_000, unit: "milliseconds", 100, 60_000, scopes: ["server"]),
            setting("scheduler.tick_secs", 10, unit: "seconds", 1, 300, scopes: ["server"]),
            setting("forge.poll_secs", 60, unit: "seconds", 10, 3_600, scopes: ["server"]),
        ]
    }

    /// The same at `company:1`: what this company sets, and what it inherits.
    static var companySettings: [ScopedSetting] {
        let set: [String: Int64] = [
            "run.token_cap": 200_000, "artifact.company_quota_bytes": 50_000_000_000,
            "approval.deadline.pr_merge": 28_800, "knowledge.budget_bytes": 6_000,
        ]
        return serverSettings.filter { $0.scopes.contains("company") }.map { setting in
            var setting = setting
            if let value = set[setting.key] {
                setting.value = value
                setting.source = "company:1"
            } else {
                setting.source = "server"
            }
            return setting
        }
    }

    /// The same at `project:1` (CIT).
    static var citSettings: [ScopedSetting] {
        companySettings.filter { $0.scopes.contains("project") }.map { setting in
            var setting = setting
            switch setting.key {
            case "run.stall_after_secs":
                setting.value = 600
                setting.source = "project:1"
            case "knowledge.budget_bytes":
                setting.value = 8_000
                setting.source = "project:1"
            default: break
            }
            return setting
        }
    }

    static func projectsPage(_ model: CompanyModel) {
        model.projects[1].name = "Mac Client"
        let page = model.projectsPage
        page.isLoaded = true
        page.selected = 1
        func repo(
            _ id: Int64, _ name: String, primary: Bool = false, token: String, _ build: String?, _ test: String?,
            _ lint: String?, _ format: String?
        ) -> RepoInfo {
            RepoInfo(
                id: id, name: name, url: "https://github.com/AinkradHQ/\(name)", defaultBranch: "development",
                isPrimary: primary, position: id, forgeKind: "github", tokenFile: "/vault/\(token).token",
                build: build, test: test, lint: lint, format: format)
        }
        page.repos = [
            1: [
                repo(
                    1, "citadel", primary: true, token: "github-ainkradhq", "cargo build --workspace",
                    "cargo test --workspace", "cargo clippy -- -D warnings", "cargo fmt --check"),
                repo(
                    2, "ainkrad-citadel-plugin", token: "github-ainkradhq", "make build", "make test", "make lint",
                    "make format-check"),
                repo(
                    3, "homebrew-ainkrad", token: "github-tap", nil, "brew audit --strict citadel",
                    "brew style Formula", nil),
            ],
            2: [repo(4, "ainkrad", primary: true, token: "github-ainkradhq", "make build", "make test", nil, nil)],
            3: [],
        ]
        page.sprintNames = [1: "S4", 3: "L2"]
        let rules = [
            "Build, test, lint and format pass in every touched repo", "Acceptance criteria each have a test",
            "QA agent verified on fresh worktrees", "Every PR of the issue merged", "No new unwrap() in server code",
        ]
        let newRule = "API changes regenerate the Swift client in ainkrad-citadel-plugin and diff the OpenAPI spec"
        let ruleList = (rules + [newRule]).map { "\"\($0)\"" }.joined(separator: ",")
        page.profiles[1] = ProfileInfo(
            stack: "Rust 1.93 · axum · SQLite (sqlx)", definitionOfDone: rules,
            protectedBranches: ["main", "staging", "development"], branchPattern: "<type>/<key>-<slug>",
            mergeMethod: "merge", mergedBy: "owner",
            environments: [
                EnvironmentInfo(name: "Local", url: "", deploy: "agents"),
                EnvironmentInfo(name: "Staging", url: "staging.citadel.ainkrad.io", deploy: "ask"),
                EnvironmentInfo(name: "Production", url: "citadel.ainkrad.io", deploy: "owner"),
            ],
            conventions: "Conventional Commits with scope", docs: ["Specs/citadel-api.md", "ADR-0001…0009"],
            models: [
                RoleModelInfo(role: "PO · Lead", model: "Opus 5.5"),
                RoleModelInfo(role: "Dev", model: "gpt-5.5", small: "mini"),
                RoleModelInfo(role: "QA", model: "Sonnet 5"),
            ],
            network: "ask", sprintApproval: "owner", permissionMode: "accept_edits", injectedBytes: 2_100,
            budgetBytes: 4_000,
            proposals: [
                ProposalInfo(
                    id: 1, field: "conventions", title: "Lint command",
                    body: "Conventional Commits with scope · lint with cargo clippy -- -D warnings && cargo deny check",
                    agentID: 7),
                ProposalInfo(
                    id: 2, field: "definition_of_done", title: "Definition of done", body: "[\(ruleList)]", agentID: 9),
            ],
            updatedAt: day("2026-10-22T09:00:00Z"))
        page.settings[1] = citSettings
        page.companySettings = companySettings
        page.declared[1] = (
            IssueInfo(id: 62, key: "CIT-62", title: "APNs push sender", projectID: 1, requirementID: 12),
            ["citadel", "ainkrad-citadel-plugin"]
        )
    }

    static func limitsPage(_ model: CompanyModel) {
        model.accounts[1]?.label = "claude-work"
        let page = model.limitsPage
        page.isLoaded = true
        page.section = .limits
        page.server = serverSettings
        page.company = companySettings
        page.below = [
            "run.stall_after_secs": [LimitOverride(scope: "project:1", owner: "CIT", value: "10 min")],
            "run.token_cap": [LimitOverride(scope: "project:3", owner: "MKT", value: "100k")],
            "runner.disk_cap_bytes": [LimitOverride(scope: "runner:2", owner: "hetzner-2", value: "80 GB")],
            "workspace.idle_secs": [LimitOverride(scope: "runner:3", owner: "ahmed-mbp", value: "12 h")],
            "artifact.company_quota_bytes": [LimitOverride(scope: "project:1", owner: "CIT", value: "20 GB")],
            "account.warn_percent": [LimitOverride(scope: "account:1", owner: "claude-work", value: "70%")],
            "knowledge.budget_bytes": [LimitOverride(scope: "project:1", owner: "CIT", value: "8 KB")],
        ]
        page.refused["artifact.company_quota_bytes"] = "max 500 GB"
        page.changes = [
            SettingChangeInfo(
                key: "run.stall_after_secs", scope: "project:1", old: 900, new: 600, at: day("2026-10-21T15:02:00Z"),
                seq: 4, agentID: nil),
            SettingChangeInfo(
                key: "artifact.company_quota_bytes", scope: "company:1", old: 20_000_000_000, new: 50_000_000_000,
                at: day("2026-10-22T06:40:00Z"), seq: 3, agentID: nil),
            SettingChangeInfo(
                key: "workspace.idle_secs", scope: "runner:3", old: 86_400, new: 43_200,
                at: day("2026-10-22T07:15:00Z"),
                seq: 2, agentID: nil),
            SettingChangeInfo(
                key: "run.token_cap", scope: "project:1", old: 200_000, new: 300_000, at: day("2026-10-22T08:02:00Z"),
                seq: 1, agentID: 7),
        ]
    }

    private static func day(_ iso: String) -> Date {
        (try? Date(iso, strategy: .iso8601)) ?? Date(timeIntervalSince1970: 0)
    }
}
