import AinkradAppKit
import AppKit
import SwiftUI

/// Screen 04: one agent — its figure and setup, the run it is on with its last tool calls, its recent runs with
/// how each ended, and a rail with its month budget, caps, setup and the week.
struct AgentView: View {
    let store: CitadelStore
    let model: CompanyModel
    let agentID: Int64
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        if let agent = model.agents[agentID] {
            HStack(spacing: 0) {
                VStack(alignment: .leading, spacing: 0) {
                    header(agent)
                    ScrollView {
                        VStack(alignment: .leading, spacing: skin.size.s14) {
                            if let run = model.agentRuns[agentID]?.first(where: \.isLive)
                                ?? model.currentRun(of: agentID).flatMap({ $0.isLive ? $0 : nil })
                            {
                                CurrentRunCard(store: store, model: model, run: run)
                            }
                            RecentRunsCard(store: store, model: model, runs: model.agentRuns[agentID] ?? [])
                        }
                        .padding(.horizontal, skin.size.s20)
                        .padding(.bottom, skin.size.s20)
                    }
                }
                .frame(maxWidth: .infinity)
                AgentRail(model: model, agent: agent)
            }
            .offlineDimmed()
        } else {
            AinkradEmptyState(icon: "person", title: "Agent not found", message: "It may have been retired.")
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    /// Big figure, name + role, department › team, harness badge, model, who it reports to; Chat, Pause, ⋯.
    private func header(_ agent: AgentInfo) -> some View {
        let place = model.place(of: agent.id)
        return HStack(alignment: .center, spacing: skin.size.s14) {
            AgentFigure(agent: agent, model: model, size: skin.size.s48, isActive: true)
            VStack(alignment: .leading, spacing: skin.size.s2) {
                HStack(alignment: .firstTextBaseline, spacing: skin.size.s6) {
                    Text(agent.name).citadelFont("t18", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                    Text(agent.role.uppercased()).citadelFont("t10", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.faint))
                }
                HStack(spacing: skin.size.s6) {
                    if let place { Text(place).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted)) }
                    AinkradBadge(text: agent.harnessName, tint: agent.figureHarness?.color ?? theme.foreground)
                    Text(agent.model).citadelFont("t12", mono: true).foregroundStyle(skin.color(skin.text.muted))
                    if let boss = model.agent(agent.reportsTo) {
                        Text("· reports to \(boss.name)").citadelFont("t12").foregroundStyle(
                            skin.color(skin.text.muted))
                    }
                }
                .lineLimit(1)
            }
            Spacer(minLength: skin.size.s10)
            AinkradButton(title: "Chat", style: .secondary, icon: "envelope.fill") { store.screen = .threads }
                .secondaryAccent().compact().fixedSize()
            // Pause / Resume needs a server endpoint (not in the API yet).
            AinkradButton(
                title: agent.isPaused ? "Resume" : "Pause", style: .secondary,
                icon: agent.isPaused ? "play.fill" : "pause.fill"
            ) {}
            .compact().fixedSize().disabled(true)
            AinkradMenuButton(items: OrgMenu.items(agent)) { Image(systemName: "ellipsis") }
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.top, skin.size.s14)
        .padding(.bottom, skin.size.s12)
    }
}

extension CompanyModel {
    /// `Engineering › Citadel Core`.
    func place(of agent: Int64) -> String? {
        for department in departments {
            if let team = department.teams.first(where: { $0.seats.contains { $0.agentID == agent } }) {
                return "\(department.name) › \(team.name)"
            }
        }
        return nil
    }
}

/// The run it is on: the last three tool calls (the live one breathing), then tokens against the per-run cap.
private struct CurrentRunCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let issue = model.issue(run.issueID)
        let calls = Transcript.items(
            model.transcripts[run.id] ?? [], runState: run.state,
            waitingRequest: model.waitingApproval(run: run.id)?.fields["request"]
        ).compactMap {
            item -> ToolCallItem? in
            if case .tool(let call) = item { return call }
            return nil
        }
        AinkradCard(onTap: { store.open(.run(run.id)) }) {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                HStack(spacing: skin.size.s8) {
                    Circle().fill(theme.accentSecondary).frame(width: skin.size.s7, height: skin.size.s7).breathing(
                        true)
                    Text(
                        skin.labelCased(
                            "Current run · \(Fmt.duration(Date().timeIntervalSince(run.startedAt ?? run.queuedAt)))")
                    )
                    .citadelFont("t11", weight: "semibold").foregroundStyle(theme.accentSecondary)
                    if let issue {
                        Text(issue.key).citadelFont("t11", mono: true).foregroundStyle(theme.accentSecondary)
                        Text(issue.title).citadelFont("t13", weight: "medium").foregroundStyle(
                            skin.color(skin.text.primary)
                        )
                        .lineLimit(1)
                    }
                    Spacer(minLength: skin.size.s8)
                    AinkradButton(title: "Open live run →", style: .ghost) { store.open(.run(run.id)) }
                        .borderless().secondaryAccent().compact().fixedSize()
                }
                ForEach(calls.suffix(3), id: \.id) { call in
                    HStack(spacing: skin.size.s6) {
                        Group {
                            if call.status == .running || call.status == .waiting {
                                Circle().fill(call.status == .waiting ? status.warning : theme.accentSecondary)
                                    .frame(width: skin.size.s6, height: skin.size.s6)
                                    .breathing(true)
                            } else if call.status == .failed {
                                Image(systemName: "xmark").foregroundStyle(status.danger)
                            } else {
                                Image(systemName: "checkmark").foregroundStyle(status.success)
                            }
                        }
                        .frame(width: skin.size.s12)
                        Text(call.name).foregroundStyle(skin.color(skin.text.primary))
                        Text(call.argument).foregroundStyle(skin.color(skin.text.muted)).lineLimit(1).truncationMode(
                            .middle)
                        if case .counts(let added, let removed) = call.result {
                            Text("+\(added)").foregroundStyle(status.success)
                            Text("−\(removed)").foregroundStyle(status.danger)
                        }
                    }
                    .citadelFont("t12", mono: true)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
                HStack(spacing: skin.size.s12) {
                    AinkradBudgetBar(
                        label: "Run tokens", value: Double(run.tokens), limit: Double(model.runCap ?? 0),
                        warnFraction: model.warnFraction)
                    Text(
                        "\(Fmt.tokens(run.tokens)) / \(Fmt.tokens(model.runCap ?? 0)) tok · \(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "unpriced")"
                    )
                    .citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint)).fixedSize()
                }
                .padding(.top, skin.size.s4)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .cardRim(theme.accentSecondary)
    }
}

/// Every run ends in a named state, and a failure says why in one line.
private struct RecentRunsCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let runs: [RunInfo]
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let ended = runs.filter { !$0.isLive }.prefix(8)
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                TileHead(title: "Recent runs", action: runs.isEmpty ? nil : "All \(runs.count) →") {
                    store.screen = .runs
                }
                if ended.isEmpty {
                    Text("No finished runs yet").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                }
                ForEach(Array(ended)) { run in
                    AinkradListRow(
                        onTap: { store.open(.run(run.id)) },
                        leading: { Circle().fill(color(run)).frame(width: skin.size.s10, height: skin.size.s10) },
                        title:
                            "\(model.issue(run.issueID)?.key ?? "#\(run.id)")  \(model.issue(run.issueID)?.title ?? "Run \(run.id)")",
                        subtitle: run.state == "succeeded" ? nil : run.terminalReason,
                        trailing: {
                            HStack(spacing: skin.size.s16) {
                                Text(run.endWord).frame(width: skin.size.s90, alignment: .trailing)
                                Text(Fmt.age((run.endedAt ?? Date()).timeIntervalSince(run.startedAt ?? run.queuedAt)))
                                    .frame(width: skin.size.s40, alignment: .trailing)
                                Text(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "—").frame(
                                    width: skin.size.s60, alignment: .trailing)
                            }
                            .citadelFont("t12", mono: true)
                            .foregroundStyle(skin.color(skin.text.muted))
                        })
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private func color(_ run: RunInfo) -> Color {
        switch run.endWord {
        case "succeeded": status.success
        case "failed", "runner lost", "timed out": status.danger
        case "cap hit": status.warning
        default: skin.color(skin.text.faint)
        }
    }
}
