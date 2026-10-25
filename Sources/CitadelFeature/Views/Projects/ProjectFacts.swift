import AinkradAppKit
import SwiftUI

/// What the list card, the hero and the Overview read about one project, derived from the company model: its team,
/// lead and agents, who works on it now, its repos, profile and work.
@MainActor
struct ProjectFacts {
    let project: ProjectInfo
    let model: CompanyModel

    var page: ProjectsPage { model.projectsPage }
    var work: ProjectWork { page.work[project.id] ?? ProjectWork() }
    var profile: ProfileInfo? { page.profiles[project.id] }
    var repos: [RepoInfo] { page.repos[project.id] ?? [] }
    var tint: (Color, Color) { ProjectLook.tint(project, in: model) }
    var glyph: String { ProjectLook.glyph(project, in: model) }
    var isScrum: Bool { project.mode != "kanban" }

    /// The owning team (the server keeps one: MISSING `team_ids`).
    var team: TeamInfo? { model.departments.flatMap(\.teams).first { $0.id == project.teamID } }
    var teams: [TeamInfo] { team.map { [$0] } ?? [] }
    var department: DepartmentInfo? { model.departments.first { $0.teams.contains { $0.id == project.teamID } } }

    var agents: [AgentInfo] {
        (team?.seats ?? []).compactMap { model.agents[$0.agentID] }.filter { $0.status != "terminated" }
    }

    var lead: AgentInfo? {
        team?.seats.first { $0.teamRole == "team_lead" }.flatMap { model.agents[$0.agentID] }
    }

    /// Agents with a live run on one of this project's issues, or working right now.
    var busy: [AgentInfo] {
        let live = Set(
            model.liveRuns.filter { run in
                run.issueID.map { id in work.items.contains { $0.id == id } || model.issues[id]?.projectID == project.id
                }
                    ?? false
            }.map(\.agentID))
        return agents.filter { live.contains($0.id) || [.working, .thinking].contains($0.figure) }
    }

    var idle: [AgentInfo] { agents.filter { agent in !busy.contains { $0.id == agent.id } } }

    var active: SprintDetail? { work.active }
    var report: SprintReportInfo? { work.report.flatMap { $0.sprintID == active?.id ? $0 : nil } }

    /// Sprint progress, or the share of issues closed on Kanban.
    var progress: Double {
        if isScrum, let report { return report.fraction }
        let all = work.items.filter { $0.state != "cancelled" }
        return all.isEmpty ? 0 : Double(all.filter(\.isDone).count) / Double(all.count)
    }

    var blocked: Int { work.items.filter(\.isBlocked).count }
    var inReview: Int { work.items.filter { $0.state == "in_review" }.count }

    /// "day 6 of 10 · 11 pts left".
    var sprintLine: String? {
        guard let active else { return nil }
        var parts: [String] = []
        if let day = active.day() { parts.append("day \(day.day) of \(day.of)") }
        if let report { parts.append("\(report.left) pts left") }
        return parts.joined(separator: " · ")
    }

    /// The burndown's points left per day, and the sprint's length.
    var burndown: (left: [Int], days: Int)? {
        guard let report, let active, !report.burndown.isEmpty else { return nil }
        return (report.burndown, max(active.day()?.of ?? report.burndown.count, report.burndown.count))
    }
}
