import Foundation

@testable import CitadelFeature

// design-lint covers Sources only; the colours below are what a server on API minor 18 stores.
extension CompanyFixture {
    /// What an API minor 18 server adds to the project screens: each project's icon, colour and teams, runtime
    /// limits, repo stacks and users, the rules as on/off, network hosts, the run context text, the cumulative flow,
    /// the five priority levels, chore and spike, acceptance criteria, epic colours and dates, and the issue's own
    /// activity. Applied after `projectWorkPage`.
    static func trancheB1Projects(_ model: CompanyModel) {
        let page = model.projectsPage
        let colors = ["#22d3ee", "#a78bfa", "#f59e0b"]
        let icons = ["⛫", "▭", "✎"]
        for index in model.projects.indices {
            model.projects[index].icon = icons[index % icons.count]
            model.projects[index].color = colors[index % colors.count]
        }
        model.projects[0].teamIDs = [1, 2]
        model.projects[0].runnerTags = ["linux", "docker"]
        model.projects[0].maxParallelRuns = 6
        model.projects[0].runTimeoutSecs = 3_600
        model.projects[0].worktreeKeepDays = 7

        let stacks = ["Rust 1.93 · axum", "Swift 6.4 · SwiftUI", "Homebrew formula"]
        for (index, repo) in (page.repos[1] ?? []).enumerated() {
            page.repos[1]?[index].stack = stacks[index % stacks.count]
        }
        page.repos[1]?[0].inUseBy = ["CIT-42", "CIT-49"]
        page.repos[1]?[1].inUseBy = ["CIT-61"]

        if var profile = page.profiles[1] {
            profile.dodRules = profile.definitionOfDone.enumerated().map { DodRuleInfo(text: $1, on: $0 != 4) }
            profile.networkHosts = ["crates.io", "static.crates.io", "github.com", "*.githubusercontent.com"]
            page.profiles[1] = profile
        }
        page.preview[1] = ProfilePreviewInfo(
            text: """
                # Citadel — project profile
                Stack: Rust 1.93 · axum · SQLite (sqlx)
                Branches: <type>/<key>-<slug> · protected main, staging, development
                Merge: merge commit · merged by the owner

                ## Definition of done
                - Build, test, lint and format pass in every touched repo
                - Acceptance criteria each have a test
                - QA agent verified on fresh worktrees
                - Every PR of the issue merged
                """, bytes: 5_400, budgetBytes: 16_384, dropped: [])
        let start = Calendar.current.startOfDay(for: Date()).addingTimeInterval(-41 * 86_400)
        page.cfd[1] = (0..<42).map { day in
            let progress = Double(day) / 41
            let done = Int(progress * 24)
            return CfdPoint(
                day: start.addingTimeInterval(Double(day) * 86_400), done: done,
                review: 2 + Int(progress * 3) % 3, active: 3 + (day / 6) % 4,
                todo: max(2, 18 - Int(progress * 10)))
        }

        guard var work = page.work[1] else { return }
        let levels = ["urgent", "high", "medium", "low", "none"]
        for index in work.items.indices { work.items[index].priorityLevel = levels[index % levels.count] }
        for (id, kind) in [(Int64(62), "chore"), (72, "spike"), (71, "chore")] {
            if let index = work.items.firstIndex(where: { $0.id == id }) { work.items[index].kind = kind }
        }
        if let index = work.items.firstIndex(where: { $0.id == 42 }) {
            work.items[index].body =
                "Resume the event stream from the last-seen id after a reconnect; replay what was missed, in order."
            work.items[index].priorityLevel = "high"
            work.items[index].criteria = [
                CriterionInfo(text: "A dropped socket resumes from Last-Event-ID", done: true),
                CriterionInfo(text: "Replay is paged and never skips a seq", done: true),
                CriterionInfo(text: "A test kills the socket mid-page"),
            ]
        }
        let today = Calendar.current.startOfDay(for: Date())
        let spans: [(Int64, String, Int, Int, Int64?)] = [
            (1, "#22d3ee", -20, 14, 12), (2, "#a78bfa", -6, 30, 12), (3, "#f59e0b", 7, 45, nil),
        ]
        for (id, color, from, to, requirement) in spans {
            guard let index = work.epics.firstIndex(where: { $0.id == id }) else { continue }
            work.epics[index].color = color
            work.epics[index].startsOn = today.addingTimeInterval(Double(from) * 86_400)
            work.epics[index].endsOn = today.addingTimeInterval(Double(to) * 86_400)
            work.epics[index].requirementID = requirement
        }
        page.work[1] = work
        page.itemActivity[42] = [
            AuditLine(
                seq: 3, at: Date().addingTimeInterval(-600), action: "issue.criteria_changed", actor: "agent:4",
                entity: nil, details: [:]),
            AuditLine(
                seq: 2, at: Date().addingTimeInterval(-7_200), action: "issue.state_changed", actor: "agent:4",
                entity: nil, details: [:]),
            AuditLine(
                seq: 1, at: Date().addingTimeInterval(-86_400), action: "issue.created", actor: "you", entity: nil,
                details: [:]),
        ]
    }

    /// The stuck cards of an API minor 18 server: the run, the usual duration and its own trail.
    static func trancheB1Stuck(_ model: CompanyModel) {
        let now = Date()
        for index in model.stuck.indices where model.stuck[index].issueID == 64 {
            model.stuck[index].runID = 430
            model.stuck[index].usualSecs = 720
            model.stuck[index].trail = [
                TrailInfo(at: now.addingTimeInterval(-1_440), what: "run #430 started on hetzner-1"),
                TrailInfo(at: now.addingTimeInterval(-900), what: "last tool call: cargo test"),
                TrailInfo(at: now.addingTimeInterval(-540), what: "no output since"),
            ]
        }
        for index in model.stuck.indices where model.stuck[index].issueID == 49 {
            model.stuck[index].usualSecs = 1_800
            model.stuck[index].trail = [
                TrailInfo(at: now.addingTimeInterval(-10_800), what: "run #422 ended runner_lost"),
                TrailInfo(at: now.addingTimeInterval(-9_000), what: "retry queued · lost on hetzner-2"),
                TrailInfo(at: now.addingTimeInterval(-7_200), what: "no runner has a free slot"),
            ]
        }
    }

    /// R-10 is paused, so the hero shows Resume.
    static func trancheB1Requirements(_ model: CompanyModel) {
        if let index = model.requirements.firstIndex(where: { $0.id == 10 }) {
            model.requirements[index].pausedAt = Date().addingTimeInterval(-1_800)
        }
    }
}
