import AinkradAppKit
import SwiftUI

/// The thread's context rail (`.th-rail`): who the agent is (runs, spend, success from its run history), its live
/// run, the issue (state, points, requirement — and the plugin's blocker / sprint controls and PRs), the files its
/// runs published here, and who is in the conversation.
struct ThreadRail: View {
    let store: CitadelStore
    let model: CompanyModel
    let key: ThreadKey
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    private var agent: AgentInfo? { model.agent(key.agentID) }
    private var issue: IssueInfo? { model.issue(key.issueID) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                if let agent { who(agent) }
                if let run = model.runs.values.filter({ $0.agentID == key.agentID && $0.isLive })
                    .max(by: { $0.queuedAt < $1.queuedAt })
                {
                    live(run)
                }
                if let issue { issueCard(issue) }
                files
                people
            }
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s14)
        }
    }

    private func card<Content: View>(tint: Color? = nil, @ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        return VStack(alignment: .leading, spacing: skin.size.s10) { content() }
            .padding(.horizontal, skin.size.s14)
            .padding(.vertical, skin.size.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [
                            (tint ?? .clear).opacity(skin.opacity.o14),
                            skin.color(.palette("foreground", skin.opacity.o03)),
                        ], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
    }

    private func head(_ title: String, _ trailing: String? = nil) -> some View {
        HStack(spacing: skin.size.s8) {
            Text(title).citadelFont("t13", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
            if let trailing {
                Text(trailing).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
            }
            Spacer(minLength: 0)
        }
    }

    private func who(_ agent: AgentInfo) -> some View {
        let runs = model.agentRuns[agent.id] ?? []
        let ended = runs.filter { !$0.isLive }
        let ok = ended.filter { $0.state == "succeeded" }.count
        let spent = ended.compactMap(\.costMicros).reduce(0, +)
        let kpis = [
            ("\(ended.count)", "runs"), (Fmt.dollars(micros: spent), "spent"),
            (ended.isEmpty ? "—" : "\(ok * 100 / ended.count)%", "success"),
        ]
        return card(tint: agent.palette.lightColor) {
            VStack(spacing: skin.size.s6) {
                AgentFigure(agent: agent, model: model, size: skin.size.s64)
                Text(agent.name).citadelFont("t15", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                Text("\(agent.roleLabel) · \(AgentLook.harnessName(agent.harness)) · \(agent.model)").citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.faint))
                HStack(spacing: skin.size.s6) {
                    ForEach(kpis, id: \.1) { value, label in
                        VStack(spacing: 0) {
                            Text(value).citadelFont("t13", weight: "semibold", mono: true)
                                .foregroundStyle(skin.color(skin.text.primary))
                            Text(label).citadelFont("t10").foregroundStyle(skin.color(skin.text.faint))
                        }
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, skin.size.s8)
                        .background(
                            skin.color(.palette("foreground", skin.opacity.o05)),
                            in: RoundedRectangle(cornerRadius: skin.size.s10))
                    }
                }
                .padding(.top, skin.size.s6)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, skin.size.s4)
        }
    }

    private func live(_ run: RunInfo) -> some View {
        let cap = model.limits["run.token_cap"]?.value ?? 0
        return AinkradTapArea(help: "Open run #\(run.id)", action: { store.open(.run(run.id)) }) {
            card {
                HStack(spacing: skin.size.s8) {
                    head("Live run", "#\(run.id)")
                    Text(Fmt.duration(Date().timeIntervalSince(run.startedAt ?? run.queuedAt))).citadelFont(
                        "t11", mono: true
                    )
                    .foregroundStyle(skin.color(skin.text.faint))
                }
                if let tool = model.toolNow[run.id] {
                    Text(tool).citadelFont("t12", mono: true).foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
                        .padding(.horizontal, skin.size.s12)
                        .frame(maxWidth: .infinity, minHeight: skin.size.s28, alignment: .leading)
                        .background(
                            skin.color(.palette("black", skin.opacity.o20)),
                            in: RoundedRectangle(cornerRadius: skin.size.s8))
                }
                if cap > 0 {
                    ProgressLine(
                        value: Double(run.tokens) / Double(cap),
                        tint: Double(run.tokens) / Double(cap) > 0.8 ? status.warning : theme.accentSecondary)
                }
                HStack(spacing: skin.size.s14) {
                    (Text("Tokens ")
                        + Text("\(Fmt.tokens(run.tokens))\(cap > 0 ? " / \(Fmt.tokens(cap))" : "")").bold()
                        .foregroundStyle(skin.color(skin.text.primary)))
                    (Text("Cost ")
                        + Text(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "—").bold()
                        .foregroundStyle(skin.color(skin.text.primary)))
                }
                .citadelFont("t11", mono: true)
                .foregroundStyle(skin.color(skin.text.faint))
            }
        }
    }

    private func issueCard(_ issue: IssueInfo) -> some View {
        let state = issue.state.isEmpty ? "to do" : issue.state.replacingOccurrences(of: "_", with: " ")
        let tint: Color =
            switch issue.state {
            case "done": status.success
            case "in_review": skin.color(skin.palette.accentViolet)
            case "blocked": status.danger
            case "in_progress": theme.accentSecondary
            default: skin.color(skin.text.muted)
            }
        let requirement = issue.requirementID.flatMap { id in model.requirements.first { $0.id == id } }
        return card {
            HStack {
                head("Issue")
                AinkradStatePill(text: state, tint: tint)
            }
            (Text(issue.key).foregroundStyle(theme.accentSecondary)
                + Text(" \(issue.title)").foregroundStyle(skin.color(skin.text.primary)))
                .citadelFont("t12_5")
            if let points = issue.points { tile("number", "Points", "\(points)") {} }
            if let requirement {
                tile("text.alignleft", "Requirement", requirement.key) {
                    model.requirementsPage.selectedID = requirement.id
                    store.screen = .requirements
                }
            }
            IssueControls(store: store, model: model, issue: issue)
            IssuePRList(store: store, model: model, issue: issue.id).padding(.horizontal, -skin.size.s20)
        }
    }

    /// `.rsd-cx`: icon tile, faint label, value.
    private func tile(_ icon: String, _ label: String, _ value: String, action: @escaping () -> Void) -> some View {
        AinkradTapArea(action: action) {
            HStack(spacing: skin.size.s10) {
                Image(systemName: icon).citadelFont("t14").foregroundStyle(status.warning)
                    .frame(width: skin.size.s32, height: skin.size.s32)
                    .background(
                        status.warning.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s10))
                VStack(alignment: .leading, spacing: 0) {
                    Text(label).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                    Text(value).citadelFont("t12_5", weight: "medium", mono: label == "Requirement")
                        .foregroundStyle(label == "Requirement" ? theme.accentSecondary : skin.color(skin.text.primary))
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s10)
            .background(
                skin.color(.palette("foreground", skin.opacity.o03)), in: RoundedRectangle(cornerRadius: skin.size.s14))
        }
    }

    private var files: some View {
        let runs = Set((model.agentRuns[key.agentID] ?? []).filter { $0.issueID == key.issueID }.map(\.id))
        let docs = model.artifactsPage.items.filter { $0.issueID == key.issueID || $0.runID.map(runs.contains) == true }
        return card {
            head("Files", "\(docs.count)")
            if docs.isEmpty {
                Text("Nothing shared yet").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            } else {
                ArtifactTiles(
                    store: store, model: model, artifacts: docs,
                    open: { artifact in
                        model.artifactsPage.selectedID = artifact.id
                        store.screen = .artifacts
                    }, singleColumn: true)
            }
        }
    }

    private var people: some View {
        card {
            head("In this conversation")
            VStack(alignment: .leading, spacing: skin.size.s6) {
                Text("You").citadelFont("t11", weight: "semibold").foregroundStyle(skin.color(skin.palette.white))
                    .padding(.horizontal, skin.size.s8)
                    .frame(height: skin.size.s22)
                    .background(
                        LinearGradient(
                            colors: [skin.color(skin.palette.accentPrimary), skin.color(skin.palette.accentViolet)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: RoundedRectangle(cornerRadius: skin.size.s6))
                if let agent {
                    HStack(spacing: skin.size.s8) {
                        AgentFigure(agent: agent, model: model, size: skin.size.s22)
                        Text(agent.name).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary))
                        Spacer(minLength: 0)
                        Text(agent.roleLabel).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    }
                }
            }
        }
    }
}
