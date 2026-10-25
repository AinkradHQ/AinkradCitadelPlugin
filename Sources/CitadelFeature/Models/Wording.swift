import AinkradAppKit
import Foundation

/// The names screens build from parts, said once: never "Product Owner (Product Owner)", "CEO · CEO",
/// "Sprint WRK WRK Sprint 1" or "1 departments".
enum Wording {
    /// "Sprint CIT S4" → "CIT S4" (the prototype says "sprint CIT S4").
    static func sprintName(_ title: String) -> String {
        title.hasPrefix("Sprint ") ? String(title.dropFirst("Sprint ".count)) : title
    }

    /// "3 agents", "1 department", "2 companies" (`plural` for an irregular one).
    static func count(_ n: some BinaryInteger, _ singular: String, plural: String? = nil) -> String {
        "\(n) \(n == 1 ? singular : plural ?? singular + "s")"
    }

    /// `name` then `detail` joined by `separator`, or just `name` when the detail is empty or says the same.
    static func name(_ name: String, _ detail: String?, separator: String = " · ") -> String {
        guard let detail, !detail.isEmpty, detail.caseInsensitiveCompare(name) != .orderedSame else { return name }
        return "\(name)\(separator)\(detail)"
    }

    /// "Mira (PO)"; just "CEO" when the name is the role.
    static func parenthesized(_ name: String, _ detail: String?) -> String {
        guard let detail, !detail.isEmpty, detail.caseInsensitiveCompare(name) != .orderedSame else { return name }
        return "\(name) (\(detail))"
    }

    /// A role as the prototype writes it: the server stores slugs, people read "Writer", "PO", "QA", "DevOps".
    static func roleLabel(_ role: String) -> String {
        let trimmed = role.trimmingCharacters(in: .whitespaces)
        if let acronym = roleAcronyms[trimmed.lowercased()] { return acronym }
        guard let first = trimmed.first else { return trimmed }
        return first.uppercased() + trimmed.dropFirst()
    }

    private static let roleAcronyms = [
        "ceo": "CEO", "cto": "CTO", "cmo": "CMO", "coo": "COO", "po": "PO", "qa": "QA", "devops": "DevOps",
    ]

    /// A sprint with its project key and the word "Sprint" each said once: "WRK Sprint 1" (named "Sprint 1" or
    /// "WRK Sprint 1"), "Sprint CIT S4" (named "S4").
    static func sprint(key: String?, name: String) -> String {
        let keyed =
            if let key, !key.isEmpty, !name.lowercased().hasPrefix(key.lowercased()) { "\(key) \(name)" } else { name }
        return keyed.localizedCaseInsensitiveContains("sprint") ? keyed : "Sprint \(keyed)"
    }
}

extension AgentInfo {
    /// "Mira (Product Owner)"; "Product Owner" when the agent is named after its role.
    var nameAndRole: String { Wording.parenthesized(name, role) }
    /// "Mira · Product Owner"; "CEO" when the name is the role.
    var nameDotRole: String { Wording.name(name, role) }
    /// The role as the prototype writes it: "Quill · Writer", "Mira · PO", "Toma · Lead".
    var roleLabel: String { Wording.roleLabel(role) }
    /// "Quill · Writer" — `nameDotRole` with the server's role slug tidied.
    var nameDotRoleLabel: String { Wording.name(name, roleLabel) }
}

extension SprintInfo {
    /// "WRK Sprint 1" or "Sprint CIT S4": the project key and the word "Sprint" each said once.
    var title: String { Wording.sprint(key: projectKey, name: name) }
}

extension CompanyModel {
    /// A run as a title: its issue ("WRK-3 Add the arm64 build"), else whose run it is ("DevOps · run #30, no
    /// issue") — never a bare "Run 30".
    func runTitle(_ run: RunInfo) -> String {
        if let issue = issue(run.issueID) { return "\(issue.key) \(issue.title)" }
        let who = agent(run.agentID)?.name ?? "Agent"
        return run.issueID == nil ? "\(who) · run #\(run.id), no issue" : "\(who) · run #\(run.id)"
    }
}

extension AinkradChartTone {
    /// A progress bar's fill, drawn with the budget bar's fixed `tone` (the kit has no progress mode): the accent
    /// while under way, success once full. Never the budget's red, which means over a limit — progress at 100% is
    /// done, not over.
    static func progress(_ value: Double, of total: Double) -> AinkradChartTone {
        total > 0 && value >= total ? .success : .accentSecondary
    }
}
