import CitadelClient
import Foundation
import Observation
import OpenAPIRuntime

extension Schemas.MergeMethod: OpenWord {}
extension Schemas.Merger: OpenWord {}
extension Schemas.Network: OpenWord {}
extension Schemas.PermissionMode: OpenWord {}
extension Schemas.SprintApproval: OpenWord {}
extension Schemas.Deploy: OpenWord {}

/// Screen 14 Project profile: the projects, and the selected one's profile, repos and limits.
@MainActor
@Observable
final class ProjectsPage {
    /// Loaded once the screen first opens.
    var isLoaded = false
    /// The project shown; `nil` is the first.
    var selected: Int64?
    /// Each project's repos, in merge order (decision #54).
    var repos: [Int64: [RepoInfo]] = [:]
    /// Each project's active sprint name ("S4"), for the list's subtitle.
    var sprintNames: [Int64: String] = [:]
    var profiles: [Int64: ProfileInfo] = [:]
    /// Each project's settings at `project:<id>`, and the company's (what a reset goes back to).
    var settings: [Int64: [ScopedSetting]] = [:]
    var companySettings: [ScopedSetting] = []
    /// An open issue of the project and the repos it declares (decision #51), for the "declare" row.
    var declared: [Int64: (issue: IssueInfo, repos: [String])] = [:]
    /// Why the last repo action was refused ("an open issue still touches it").
    var problem: ServerAnswer?
    /// Each project's permission policy (API minor 11): its mode and allowlist.
    var policies: [Int64: PolicyInfo] = [:]
    /// Each project's profile history once "History →" opened it, newest first.
    var history: [Int64: [ProfileChangeInfo]] = [:]
    /// Each project's knowledge entries (API minor 16), oldest first, once its Knowledge group first loads.
    var knowledge: [Int64: [KnowledgeInfo]] = [:]
    /// The project page open over the list (`#/projects/<KEY>`); `nil` is the list.
    var openProject: Int64?
    var tab: ProjectTab = .overview
    /// The configuration drawer's tab, or the work item it shows; `nil` is closed.
    var drawer: ProjectDrawer?
    /// Each opened project's work: issues, epics, sprints, velocity, capacity, flow.
    var work: [Int64: ProjectWork] = [:]
    /// The Board and Backlog toolbar.
    var filter = WorkFilter()
    /// The item drawer's runs and activity, per issue.
    var itemRuns: [Int64: [RunInfo]] = [:]
    var itemActivity: [Int64: [AuditLine]] = [:]
    /// Each project's cumulative flow, and the text a run on it is given (API minor 18).
    var cfd: [Int64: [CfdPoint]] = [:]
    var preview: [Int64: ProfilePreviewInfo] = [:]
}

enum ProjectTab: String, CaseIterable, Hashable, Sendable {
    case overview, board, backlog, sprints, timeline, reports

    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .overview: "square.grid.2x2"
        case .board: "rectangle.split.3x1"
        case .backlog: "line.3.horizontal"
        case .sprints: "clock"
        case .timeline: "text.alignleft"
        case .reports: "chart.bar"
        }
    }
}

enum ConfigTab: String, CaseIterable, Hashable, Sendable {
    case teams, repos, rules, runtime, limits, docs, context

    var title: String { rawValue.capitalized }
    var icon: String {
        switch self {
        case .teams: "person.2"
        case .repos: "arrow.triangle.branch"
        case .rules: "checklist"
        case .runtime: "server.rack"
        case .limits: "gauge.with.needle"
        case .docs: "doc"
        case .context: "eye"
        }
    }
}

enum ProjectDrawer: Hashable, Sendable {
    case config(ConfigTab)
    case item(Int64)
}

/// The Board / Backlog toolbar: type, epic, and the board's grouping.
struct WorkFilter: Equatable, Sendable {
    /// `nil` is All.
    var kind: String?
    var epic: Int64?
    /// `none`, `epic`, `agent`.
    var group = "none"

    func apply(_ items: [WorkItem]) -> [WorkItem] {
        items.filter { (kind == nil || $0.kind == kind) && (epic == nil || $0.epicID == epic) }
    }
}

/// One git repo of a project (decision #51).
struct RepoInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    var url: String
    var defaultBranch: String
    var isPrimary: Bool
    var position: Int64
    /// `github`, `gitlab`; `nil` without forge config.
    var forgeKind: String?
    /// The token's reference in the server vault (never the token).
    var tokenFile: String?
    var build: String?
    var test: String?
    var lint: String?
    var format: String?
    /// What it is built with, "Rust · Node" (API minor 18).
    var stack: String? = nil
    /// The keys of the issues working it now (API minor 18).
    var inUseBy: [String] = []

    /// The URL without its scheme: `github.com/AinkradHQ/citadel`.
    var shortURL: String {
        url.replacingOccurrences(of: "https://", with: "").replacingOccurrences(of: "http://", with: "")
            .replacingOccurrences(of: ".git", with: "")
    }

    /// "vault: github-ainkradhq".
    var vaultLine: String? {
        tokenFile.map { "vault: \(URL(fileURLWithPath: $0).deletingPathExtension().lastPathComponent)" }
    }

    /// Build, test, lint, format in that order, each with its command (`nil` = none).
    var commands: [(label: String, command: String?)] {
        [("Build", build), ("Test", test), ("Lint", lint), ("Format", format)]
    }
}

/// A project's profile (E15.13) as the screen reads it: what every run on it is given.
struct ProfileInfo: Equatable, Sendable {
    var stack = ""
    var definitionOfDone: [String] = []
    var protectedBranches: [String] = []
    var branchPattern = ""
    /// `merge`, `squash`, `rebase`.
    var mergeMethod = "merge"
    /// `owner`, `product_owner`, `lead`.
    var mergedBy = "owner"
    var environments: [EnvironmentInfo] = []
    /// The definition of done with each rule on or off (API minor 18); empty from an older server.
    var dodRules: [DodRuleInfo] = []
    /// Hosts agents may reach while the network is `ask` (API minor 18).
    var networkHosts: [String] = []
    var conventions = ""
    var docs: [String] = []
    var models: [RoleModelInfo] = []
    /// `off`, `ask`, `on`.
    var network = "off"
    /// Who approves the plan (decision #40): `owner` or `product_owner`.
    var sprintApproval = "owner"
    /// `ask`, `accept_edits`, `sandboxed`.
    var permissionMode = "ask"
    var injectedBytes: Int64 = 0
    var budgetBytes: Int64 = 0
    var proposals: [ProposalInfo] = []
    var updatedAt: Date?
}

struct DodRuleInfo: Equatable, Sendable {
    var text: String
    var on = true
}

struct EnvironmentInfo: Equatable, Sendable {
    var name: String
    var url: String
    /// `agents`, `ask`, `owner`.
    var deploy: String
}

struct RoleModelInfo: Equatable, Sendable {
    var role: String
    var model: String
    var small: String?
    var large: String?
}

/// An agent's pending change to one profile field (decision #48: a person accepts it, never automatically).
struct ProposalInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    /// The profile field it changes: `definition_of_done`, `conventions`, ….
    var field: String
    var title: String
    /// The new value: JSON for a list or choice field, plain text for a text field.
    var body: String
    var agentID: Int64?
    /// Why the agent proposes it, in one line, when it said.
    var rationale: String?
}

/// One step of a profile's history ("History →"): a change, or an agent's proposal of one and its decision.
struct ProfileChangeInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var at: Date
    /// The agent that acted; `nil` for a person or the server.
    var agentID: Int64?
    /// A person (the admin) acted.
    var byPerson: Bool
    /// `project.profile_set`, `knowledge.proposed`, `knowledge.accepted`, `knowledge.rejected`.
    var action: String
    /// The fields a change set.
    var fields: [String] = []
    /// A proposal's title and field.
    var title: String?
    var field: String?
    /// A proposal's rationale, or a decision's reason.
    var why: String?

    /// "changed lint, test", "proposed Lint command", "rejected Lint command".
    var line: String {
        switch action {
        case "project.profile_set":
            let names = fields.map { $0.replacingOccurrences(of: "_", with: " ") }
            return names.isEmpty ? "changed the profile" : "changed \(names.joined(separator: ", "))"
        case "knowledge.proposed": return "proposed \(title ?? field ?? "a change")"
        case "knowledge.accepted": return "accepted \(title ?? "a proposal")"
        case "knowledge.rejected": return "rejected \(title ?? "a proposal")"
        default: return action
        }
    }
}

extension RepoInfo {
    init(_ repo: Schemas.Repo) {
        self.init(
            id: repo.id, name: repo.name, url: repo.url, defaultBranch: repo.defaultBranch, isPrimary: repo.primary,
            position: repo.position, forgeKind: repo.forge?.kind, tokenFile: repo.forge?.tokenFile,
            build: repo.commands.build.nonEmpty, test: repo.commands.test.nonEmpty, lint: repo.commands.lint.nonEmpty,
            format: repo.commands.format.nonEmpty, stack: repo.stack.nonEmpty, inUseBy: repo.inUseBy ?? [])
    }
}

extension ProjectInfo {
    init(_ project: Schemas.Project) {
        self.init(
            id: project.id, key: project.key, name: project.name, teamID: project.teamId, mode: project.mode.word,
            icon: project.icon.nonEmpty, color: project.color.nonEmpty, logoURL: project.logoUrl.nonEmpty,
            teamIDs: project.teamIds ?? [], runnerTags: project.runnerTags ?? [],
            maxParallelRuns: project.maxParallelRuns.map(Int.init),
            runTimeoutSecs: project.runTimeoutSecs.map(Int.init),
            worktreeKeepDays: project.worktreeKeepDays.map(Int.init))
    }
}

extension ProfileInfo {
    init(_ view: Schemas.ProjectProfile) {
        let profile = view.profile
        self.init(
            stack: profile.stack ?? "", definitionOfDone: profile.definitionOfDone ?? [],
            protectedBranches: profile.protectedBranches ?? [], branchPattern: profile.branchPattern ?? "",
            mergeMethod: profile.mergeMethod?.word ?? "merge", mergedBy: profile.mergedBy?.word ?? "owner",
            environments: (profile.environments ?? []).map {
                EnvironmentInfo(name: $0.name, url: $0.url ?? "", deploy: $0.deploy?.word ?? "ask")
            },
            dodRules: (profile.definitionOfDoneRules ?? []).map { DodRuleInfo(text: $0.text, on: $0.on ?? true) },
            networkHosts: profile.networkHosts ?? [],
            conventions: profile.conventions ?? "", docs: profile.docs ?? [],
            models: (profile.models ?? []).map {
                RoleModelInfo(role: $0.role, model: $0.model, small: $0.small, large: $0.large)
            },
            network: profile.network?.word ?? "off", sprintApproval: view.sprintApproval.word,
            permissionMode: view.permissionMode.word, injectedBytes: view.injectedBytes,
            budgetBytes: view.budgetBytes,
            proposals: view.proposals.map {
                ProposalInfo(
                    id: $0.id, field: $0.field, title: $0.title, body: $0.body, agentID: $0.proposedBy,
                    rationale: $0.rationale)
            },
            updatedAt: view.updatedAt)
    }

    /// A proposal as the card shows it: the value it replaces (struck through) and the new one; a list field
    /// shows only what it adds ("+ API changes regenerate…"), or removes.
    func diff(_ proposal: ProposalInfo) -> (old: String?, new: String) {
        let list: [String]? =
            switch proposal.field {
            case "definition_of_done": definitionOfDone
            case "protected_branches": protectedBranches
            case "docs": docs
            default: nil
            }
        if let list, let data = proposal.body.data(using: .utf8),
            let proposed = try? JSONDecoder().decode([String].self, from: data)
        {
            let added = proposed.filter { !list.contains($0) }
            let removed = list.filter { !proposed.contains($0) }
            if !added.isEmpty { return (nil, added.joined(separator: " · ")) }
            return (removed.joined(separator: " · "), "removed")
        }
        let old: String? =
            switch proposal.field {
            case "stack": stack
            case "conventions": conventions
            case "branch_pattern": branchPattern
            case "merge_method": mergeMethod
            case "merged_by": mergedBy
            case "network": network
            default: nil
            }
        let new = proposal.body.trimmingCharacters(in: CharacterSet(charactersIn: "\""))
        return (old.flatMap { $0.isEmpty ? nil : $0 }, new)
    }
}

extension ProjectsPage {
    /// "CIT Scrum · S4 · 3 repos", "MKT Scrum · L2 · no repo".
    func subtitle(_ project: ProjectInfo) -> String {
        let mode = project.mode.prefix(1).uppercased() + project.mode.dropFirst()
        let count = repos[project.id]?.count
        let repoText = count.map { $0 == 0 ? "no repo" : $0 == 1 ? "1 repo" : "\($0) repos" }
        return ([project.key + " " + mode, sprintNames[project.id], repoText].compactMap { $0 })
            .joined(separator: " · ")
    }

    /// The project's settings an override can sit on (`project` in their scopes), and how many it overrides.
    func limits(_ project: Int64) -> [ScopedSetting] {
        (settings[project] ?? []).filter { $0.scopes.contains("project") }
    }

    func overriddenCount(_ project: Int64) -> Int {
        limits(project).filter { $0.isSet(at: "project:\(project)") }.count
    }

    /// The company's value of `key` — what a project override shadows, and what ↺ goes back to.
    /// Read as the company's ("company 15 min") whichever scope the company itself inherits it from.
    func inherited(_ key: String) -> ScopedSetting? {
        companySettings.first { $0.key == key }.map {
            var setting = $0
            setting.source = "company"
            return setting
        }
    }
}

extension Optional where Wrapped == String {
    /// `nil` for an empty string.
    var nonEmpty: String? { self.flatMap { $0.isEmpty ? nil : $0 } }
}

extension ProfileChangeInfo {
    init(_ change: Schemas.ProfileChange) {
        let details = change.details.value
        func text(_ key: String) -> String? { (details[key] as? String).flatMap { $0.isEmpty ? nil : $0 } }
        var agent: Int64?
        var person = false
        switch change.actor {
        case .agent(let a): agent = a.agentId
        case .user: person = true
        case .runner, .system: break
        }
        self.init(
            id: change.seq, at: change.at, agentID: agent, byPerson: person, action: change.action,
            fields: (details["fields"] as? [Any])?.compactMap { $0 as? String } ?? [], title: text("title"),
            field: text("profile_field"), why: text("rationale") ?? text("reason"))
    }
}
