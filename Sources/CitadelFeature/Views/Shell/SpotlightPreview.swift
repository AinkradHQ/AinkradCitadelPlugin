import AinkradAppKit
import SwiftUI

/// ⌘K's right pane: a preview of the selected row, per kind, with its Open (↵) and second (⌘↵) buttons.
struct SpotlightPreview: View {
    let store: CitadelStore
    let model: CompanyModel
    let item: SearchItem
    let open: (_ alt: Bool) -> Void
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s12) {
                header
                content
                HStack(spacing: skin.size.s8) {
                    AinkradDockButton("Open ↵", tone: .primary, height: skin.size.s30, fillsWidth: true) { open(false) }
                    if let alt = item.altTitle {
                        AinkradDockButton("\(alt) ⌘↵", height: skin.size.s30, fillsWidth: true) { open(true) }
                    }
                }
                .padding(.top, skin.size.s4)
            }
            .padding(skin.size.s16)
        }
        .scrollIndicators(.never)
        // A project's sprint and repos come from its page's data, which ⌘K loads for the selected row only.
        .task(id: item.id) {
            guard case .project(let id) = item.kind else { return }
            if model.projectsPage.repos.isEmpty { store.loadProjectsPage() }
            if model.projectsPage.work[id] == nil { store.loadWork(id) }
        }
    }

    // MARK: - Header

    @ViewBuilder private var header: some View {
        switch item.kind {
        case .agent(let id):
            if let agent = model.agent(id) {
                VStack(spacing: skin.size.s8) {
                    AgentFigure(agent: agent, model: model, size: skin.size.s80 + skin.size.s4, isActive: true)
                    Text(agent.name).citadelFont("t15", weight: "semibold").foregroundStyle(
                        skin.color(skin.text.primary))
                    Text("\(agent.role) · \(agent.harnessName) · \(agent.model)").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                }
                .frame(maxWidth: .infinity)
            }
            agentTiles(id)
        case .run(let id):
            if let run = run(id), let agent = model.agent(run.agentID) {
                HStack(spacing: skin.size.s12) {
                    AgentFigure(agent: agent, model: model, size: skin.size.s64, isActive: run.isLive)
                    titleBlock(item.title, item.subtitle)
                }
            } else {
                titleBlock(item.title, item.subtitle)
            }
        case .requirement(let id):
            if let requirement = model.requirements.first(where: { $0.id == id }) {
                HStack(spacing: skin.size.s12) {
                    let fraction =
                        requirement.points > 0 ? Double(requirement.donePoints) / Double(requirement.points) : nil
                    AinkradRingGauge(
                        value: fraction, tint: skin.color(skin.palette.accentSecondary), diameter: skin.size.s56,
                        lineWidth: skin.size.s6
                    ) {
                        Text(fraction.map { "\(Int($0 * 100))%" } ?? "—").citadelFont("t11", weight: "bold", mono: true)
                    }
                    titleBlock(item.title, item.subtitle)
                }
            }
        default:
            titleBlock(item.title, item.subtitle)
        }
    }

    private func titleBlock(_ title: String, _ subtitle: String) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s3) {
            Text(title).citadelFont("t15", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                .fixedSize(horizontal: false, vertical: true)
            Text(subtitle).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        }
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        switch item.kind {
        case .agent(let id):
            if let run = model.currentRun(of: id), run.isLive {
                card("Now") { runFacts(run) }
            } else if let agent = model.agent(id) {
                card("Now") {
                    Text(model.orgLine(agent).text).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                }
            }
        case .run(let id):
            if let run = run(id) { card(run.isLive ? "Live" : "Run") { runFacts(run) } }
        case .requirement(let id):
            let issues = model.issues.values.filter { $0.requirementID == id }.sorted { $0.id < $1.id }
            card("Issues · \(issues.count)") {
                ForEach(issues.prefix(8)) { issue in
                    HStack(spacing: skin.size.s6) {
                        if case .agent(let agent)? = issue.nextActor, let figure = model.agent(agent) {
                            AgentFigure(agent: figure, model: model, size: skin.size.s18)
                        }
                        Text(issue.key).citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.palette.accentSecondary))
                        Text(issue.title).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                        Spacer(minLength: skin.size.s4)
                        AinkradStatePill(
                            text: issue.state.replacingOccurrences(of: "_", with: " "),
                            tint: stateTone(issue.state))
                    }
                }
                if issues.isEmpty {
                    Text("Planning — issues appear once the plan is approved.").citadelFont("t12")
                        .foregroundStyle(skin.color(skin.text.faint))
                }
            }
        case .issue(let id):
            if let issue = model.issues[id] {
                card("Issue") {
                    fact("State", issue.state.replacingOccurrences(of: "_", with: " "))
                    fact("Points", issue.points.map(String.init) ?? "—")
                    fact("Requirement", model.requirements.first { $0.id == issue.requirementID }?.key ?? "—")
                }
            }
        case .approval(let id):
            if let approval = model.approvals.first(where: { $0.id == id }) {
                let line = ToolLine.line(approval.fields)
                if !line.isEmpty {
                    Text("$ \(line)").citadelFont("t11", mono: true).foregroundStyle(
                        skin.color(skin.palette.accentSecondary)
                    )
                    .padding(skin.size.s10)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(
                        skin.color(.palette("black", skin.opacity.o30)),
                        in: RoundedRectangle(cornerRadius: skin.size.s10))
                }
                card("Asked") {
                    fact("By", model.agent(approval.agentID ?? approval.requestedBy)?.name ?? "—")
                    fact("Run", approval.fields["run"].map { "#\($0)" } ?? "—")
                    fact("Issue", model.issue(approval.issueID)?.key ?? approval.fields["key"] ?? "—")
                }
            }
        case .stuck(let index):
            if model.stuck.indices.contains(index) {
                let stuck = model.stuck[index]
                card("Why") {
                    Text(stuck.reason).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary))
                    Text(stuck.action).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                    if let repair = stuck.repair {
                        Text("Suggested: \(repair)").citadelFont("t11").foregroundStyle(status.warning)
                    }
                }
            }
        case .project(let id):
            if let project = model.projects.first(where: { $0.id == id }) {
                card("Project") {
                    fact("Key", project.key)
                    fact("Cadence", project.mode == "kanban" ? "Kanban" : "Sprints")
                }
                projectSprint(id, kanban: project.mode == "kanban")
                projectRepos(id)
            }
        case .artifact(let id):
            if let artifact = model.artifactsPage.items.first(where: { $0.id == id }) {
                card("Artifact") {
                    fact("Type", artifact.type)
                    fact("Size", ScopedSetting.bytes(artifact.size))
                    fact("By", artifact.agentID.flatMap { model.agent($0)?.name } ?? "—")
                    fact("When", Fmt.age(-artifact.createdAt.timeIntervalSinceNow) + " ago")
                }
            }
        case .screen, .action:
            EmptyView()
        }
    }

    /// The agent's month budget as a ring, and its runs and spend today (prototype `sp-tiles`).
    private func agentTiles(_ agent: Int64) -> some View {
        let budget = model.monthBudget(of: agent)
        let stats = model.stats(of: agent)
        return HStack(alignment: .top, spacing: skin.size.s8) {
            VStack(spacing: skin.size.s4) {
                AinkradRingGauge(
                    value: budget?.shownFraction, tint: skin.color(skin.palette.accentPrimary), diameter: skin.size.s40,
                    lineWidth: skin.size.s5
                ) {
                    Text(budget.map { "\(Int($0.shownFraction * 100))%" } ?? "—")
                        .citadelFont("t10_5", weight: "bold", mono: true)
                }
                Text(budget.map { "\($0.spentWord) of \($0.capWord)" } ?? "No month budget")
                    .citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    .lineLimit(1)
            }
            .frame(maxWidth: .infinity)
            tile("\(stats.todayRuns)", "runs today")
            tile(Fmt.dollars(micros: stats.todayMicros), "spent today")
        }
        .padding(.top, skin.size.s4)
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(spacing: skin.size.s2) {
            Text(value).citadelFont("t13", weight: "semibold", mono: true).foregroundStyle(
                skin.color(skin.text.primary)
            ).lineLimit(1)
            Text(label).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
        }
        .frame(maxWidth: .infinity)
    }

    /// The project's active sprint: its name, day, points done against committed, and the bar (prototype `sp-card`).
    @ViewBuilder private func projectSprint(_ id: Int64, kanban: Bool) -> some View {
        if let work = model.projectsPage.work[id] {
            if let sprint = work.active {
                let items = work.items(in: sprint.id)
                let committed = items.reduce(0) { $0 + ($1.points ?? 0) }
                let completed = items.filter(\.isDone).reduce(0) { $0 + ($1.points ?? 0) }
                let day = sprint.day().map { "day \($0.day) of \($0.of)" }
                card(["Sprint", day].compactMap { $0 }.joined(separator: " · ")) {
                    HStack {
                        Text(Wording.sprintName(sprint.name)).citadelFont("t12", weight: "medium").foregroundStyle(
                            skin.color(skin.text.primary))
                        Spacer(minLength: skin.size.s4)
                        Text("\(completed)/\(committed) pts").citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.text.muted))
                    }
                    AinkradBudgetBar(
                        label: "Sprint \(sprint.name)", value: Double(completed), limit: Double(max(committed, 1)),
                        warnFraction: nil, showsHardLimit: false,
                        tone: .progress(Double(completed), of: Double(committed)))
                }
            } else {
                card("Sprint") {
                    Text(kanban ? "Kanban · no sprint" : "No active sprint").citadelFont("t12").foregroundStyle(
                        skin.color(skin.text.faint))
                }
            }
        }
    }

    private func projectRepos(_ id: Int64) -> some View {
        card("Repos") {
            let repos = model.projectsPage.repos[id] ?? []
            if repos.isEmpty {
                Text("No repos").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
            } else {
                AinkradFlowLayout(spacing: skin.size.s6) {
                    ForEach(repos) { repo in
                        Text(repo.name).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.muted))
                            .padding(.horizontal, skin.size.s6)
                            .padding(.vertical, skin.size.s2)
                            .background(
                                skin.color(.palette("foreground", skin.opacity.o07)),
                                in: RoundedRectangle(cornerRadius: skin.size.s6))
                    }
                }
            }
        }
    }

    /// An issue state's tone (prototype `SP_ST`): done green, in flight blue, planning amber, blocked red, the rest muted.
    private func stateTone(_ state: String) -> Color {
        switch state {
        case "done": status.success
        case "in_progress", "in_review", "review": skin.color(skin.palette.accentPrimary)
        case "plan", "planning": status.warning
        case "blocked": status.danger
        default: skin.color(skin.text.muted)
        }
    }

    private func runFacts(_ run: RunInfo) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            if let issue = model.issue(run.issueID) {
                Text("\(issue.key) · \(issue.title)").citadelFont("t12", weight: "medium")
                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(2)
            }
            AinkradBudgetBar(
                label: "Run tokens", value: Double(run.tokens), limit: Double(model.runCap ?? max(run.tokens, 1)),
                warnFraction: model.warnFraction, showsHardLimit: false)
            Text(
                "\(Fmt.tokens(run.tokens)) of \(model.runCap.map(Fmt.tokens) ?? "—") tok · \(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "unpriced")"
            )
            .citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.muted))
            if run.isLive {
                Text("▸ \(model.toolNow[run.id] ?? run.state)").citadelFont("t11", mono: true)
                    .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            } else {
                Text(run.endWord).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
        }
    }

    private func card<Content: View>(_ title: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s8) {
            Text(title).citadelFont("t10_5", weight: "semibold").foregroundStyle(skin.color(skin.text.faint))
            content()
        }
        .padding(skin.size.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s14))
    }

    private func fact(_ label: String, _ value: String) -> some View {
        HStack {
            Text(label).citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
            Spacer()
            Text(value).citadelFont("t12", weight: "medium").foregroundStyle(skin.color(skin.text.primary))
        }
    }

    private func run(_ id: Int64) -> RunInfo? { model.runs[id] ?? model.companyRuns?.first { $0.id == id } }
}
