import Foundation

/// What ⌘K finds (prototype `search.js`): scopes, ranked rows, the open and second actions.
enum SearchScope: String, CaseIterable, Identifiable {
    case all, agents, runs, requirements, issues, projects, artifacts, goTo, actions
    var id: Self { self }

    var title: String {
        switch self {
        case .all: "All"
        case .agents: "Agents"
        case .runs: "Runs"
        case .requirements: "Requirements"
        case .issues: "Issues"
        case .projects: "Projects"
        case .artifacts: "Artifacts"
        case .goTo: "Go to"
        case .actions: "Actions"
        }
    }
}

/// One row: its group (the header it sits under), what it is, and what ↵ / ⌘↵ do.
struct SearchItem: Identifiable {
    enum Kind: Equatable {
        case agent(Int64), run(Int64), requirement(Int64), issue(Int64), project(Int64), approval(Int64), stuck(Int)
        case screen(Screen), action(String)
    }

    let id: String
    let kind: Kind
    let scope: SearchScope
    /// The header it groups under ("Needs you", "Live runs", "Agents", …).
    let group: String
    let title: String
    let subtitle: String
    let meta: String?
    let glyph: String
    /// ⌘↵'s label ("Run", "Agent", "Chat"), when it has one.
    var altTitle: String?
}

/// The ranking: label prefix 5 › word start 4 › substring 3 › subtitle 2 › letters in order 1 › no match 0.
func searchScore(_ query: String, title: String, subtitle: String) -> Int {
    let q = query.lowercased().trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return 1 }
    let t = title.lowercased()
    if t.hasPrefix(q) { return 5 }
    if t.split(whereSeparator: { !$0.isLetter && !$0.isNumber }).contains(where: { $0.hasPrefix(q) }) { return 4 }
    if t.contains(q) { return 3 }
    if subtitle.lowercased().contains(q) { return 2 }
    // ponytail: letters-in-order fuzzy match only for queries of 3+ characters, so short queries stay tight.
    guard q.count >= 3 else { return 0 }
    var rest = Substring(t)
    for ch in q {
        guard let found = rest.firstIndex(of: ch) else { return 0 }
        rest = rest[rest.index(after: found)...]
    }
    return 1
}

/// The ranges of `title` that match `query` (case-insensitive), for the highlight.
func searchHighlight(_ query: String, in title: String) -> Range<String.Index>? {
    let q = query.trimmingCharacters(in: .whitespaces)
    guard !q.isEmpty else { return nil }
    return title.range(of: q, options: .caseInsensitive)
}

extension CompanyModel {
    /// Every searchable row, in the prototype's group order.
    func searchItems() -> [SearchItem] {
        var items: [SearchItem] = []
        for approval in approvals {
            let summary = summary(approval)
            items.append(
                SearchItem(
                    id: "ap\(approval.id)", kind: .approval(approval.id), scope: .actions, group: "Needs you",
                    title: summary.title, subtitle: approval.kind.replacingOccurrences(of: "_", with: " "), meta: "approve",
                    glyph: "✓", altTitle: approval.fields["run"] == nil ? nil : "Run"))
        }
        for (index, item) in stuck.enumerated() {
            let key = issue(item.issueID)?.key
            items.append(
                SearchItem(
                    id: "st\(index)", kind: .stuck(index), scope: .issues, group: "Needs you",
                    title: [key, item.reason].compactMap { $0 }.joined(separator: " "), subtitle: item.action, meta: "stuck",
                    glyph: "⚑"))
        }
        for run in liveRuns {
            let who = agent(run.agentID)?.name ?? "Agent"
            items.append(
                SearchItem(
                    id: "lr\(run.id)", kind: .run(run.id), scope: .runs, group: "Live runs",
                    title: "\(who) · \(issue(run.issueID)?.title ?? runTitle(run))",
                    subtitle: "#\(run.id) · \(issue(run.issueID)?.key ?? "") · \(toolNow[run.id] ?? run.state)", meta: "live",
                    glyph: "▶", altTitle: "Agent"))
        }
        for agent in agents.values.sorted(by: { $0.name < $1.name }) where agent.status != "terminated" {
            items.append(
                SearchItem(
                    id: "ag\(agent.id)", kind: .agent(agent.id), scope: .agents, group: "Agents", title: agent.name,
                    subtitle: "\(agent.role) · \(agent.harnessName) · \(agent.model)", meta: orgLine(agent).text
                        .components(separatedBy: " · ").last, glyph: "◉", altTitle: "Chat"))
        }
        for requirement in requirements {
            items.append(
                SearchItem(
                    id: "rq\(requirement.id)", kind: .requirement(requirement.id), scope: .requirements,
                    group: "Requirements", title: "\(requirement.key) \(requirement.title)",
                    subtitle: "\(requirement.donePoints) / \(requirement.points) pts · \(requirement.state.replacingOccurrences(of: "_", with: " "))",
                    meta: requirement.state == "plan_review" ? "plan" : nil, glyph: "◆"))
        }
        for issue in issues.values.sorted(by: { $0.id > $1.id }) {
            items.append(
                SearchItem(
                    id: "is\(issue.id)", kind: .issue(issue.id), scope: .issues, group: "Issues",
                    title: "\(issue.key) \(issue.title)", subtitle: issue.state.replacingOccurrences(of: "_", with: " "),
                    meta: issue.points.map { "\($0) pts" }, glyph: "◇"))
        }
        for run in (companyRuns ?? []) where !run.isLive {
            let who = agent(run.agentID)?.name ?? "Agent"
            items.append(
                SearchItem(
                    id: "rn\(run.id)", kind: .run(run.id), scope: .runs, group: "Runs",
                    title: "#\(run.id) \(who) · \(issue(run.issueID)?.key ?? runTitle(run))", subtitle: run.endWord, meta: nil,
                    glyph: "▶", altTitle: "Agent"))
        }
        for project in projects {
            items.append(
                SearchItem(
                    id: "pj\(project.id)", kind: .project(project.id), scope: .projects, group: "Projects",
                    title: project.name, subtitle: "\(project.key) · \(project.mode)", meta: project.key, glyph: "▦"))
        }
        for screen in Screen.allCases {
            items.append(
                SearchItem(
                    id: "go\(screen.rawValue)", kind: .screen(screen), scope: .goTo, group: "Go to", title: screen.title,
                    subtitle: "Open \(screen.title)", meta: Screen.allCases.firstIndex(of: screen).flatMap { $0 < 9 ? "⌘\($0 + 1)" : nil },
                    glyph: "→"))
        }
        for (key, title, hint) in [
            ("newRequirement", "New requirement…", "⌘N"), ("pauseAll", "Pause all runs", nil),
            ("switchCompany", "Switch company…", "⌘⇧O"), ("shortcuts", "Keyboard shortcuts", "?"),
            ("settings", "Company settings", nil),
        ] {
            items.append(
                SearchItem(
                    id: "ac\(key)", kind: .action(key), scope: .actions, group: "Actions", title: title, subtitle: "Action",
                    meta: hint, glyph: "⌘"))
        }
        return items
    }

    /// The rows for a query and scope, ranked; groups ordered by their best match. Without a query, All shows only
    /// Needs you, Live runs, Go to and Actions.
    func searchResults(_ query: String, scope: SearchScope) -> [SearchItem] {
        let trimmed = query.trimmingCharacters(in: .whitespaces)
        let pool = searchItems().filter { scope == .all || $0.scope == scope || (scope == .actions && $0.group == "Needs you") }
        if trimmed.isEmpty {
            let quiet = scope == .all ? pool.filter { ["Needs you", "Live runs", "Go to", "Actions"].contains($0.group) } : pool
            return Array(quiet.prefix(30))
        }
        let scored = pool.map { ($0, searchScore(trimmed, title: $0.title, subtitle: $0.subtitle)) }.filter { $0.1 > 0 }
        let best = Dictionary(grouping: scored, by: \.0.group).mapValues { $0.map(\.1).max() ?? 0 }
        return scored.sorted {
            let (a, b) = (best[$0.0.group] ?? 0, best[$1.0.group] ?? 0)
            if a != b { return a > b }
            if $0.0.group != $1.0.group { return $0.0.group < $1.0.group }
            return $0.1 > $1.1
        }
        .prefix(40).map(\.0)
    }
}
