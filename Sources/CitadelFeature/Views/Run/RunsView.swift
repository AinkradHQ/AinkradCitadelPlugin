import AinkradAppKit
import SwiftUI

/// The Runs screen: the company's runs, newest first — state, agent, issue, how long and what it used; a row
/// opens the run (screen 05). Read from `GET /companies/{id}/runs` and kept current by run events.
struct RunsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let runs = model.companyRuns ?? []
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Runs", crumb: crumb(runs))
            Group {
                if model.companyRuns == nil {
                    FirstLoadView()
                } else if runs.isEmpty {
                    AinkradEmptyState(
                        icon: "play", title: "No runs yet",
                        message: "A run starts when an agent is woken on an issue; it shows here, newest first.")
                } else {
                    ScrollView {
                        LazyVStack(alignment: .leading, spacing: skin.size.s2) {
                            ForEach(runs) { run in row(run) }
                        }
                        .padding(.horizontal, skin.size.s14)
                        .padding(.bottom, skin.size.s14)
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offlineDimmed()
        }
        .onAppear { store.loadRunsPage() }
    }

    /// "3 live · 50 newest".
    private func crumb(_ runs: [RunInfo]) -> Text {
        let live = runs.filter(\.isLive).count
        return Text("\(live) live · \(Wording.count(runs.count, "run")) newest first")
            .foregroundStyle(skin.color(skin.text.muted))
    }

    private func row(_ run: RunInfo) -> some View {
        let agent = model.agent(run.agentID)
        let issue = model.issue(run.issueID)
        return AinkradListRow(
            onTap: { store.open(.run(run.id)) },
            leading: {
                if let agent {
                    AgentFigure(agent: agent, model: model, size: skin.size.s28)
                } else {
                    Circle().fill(color(run)).frame(width: skin.size.s10, height: skin.size.s10)
                }
            },
            title: issue.map { "\($0.key)  \($0.title)" } ?? model.runTitle(run),
            subtitle: subtitle(run, agent: agent),
            trailing: {
                HStack(spacing: skin.size.s16) {
                    Text(run.isLive ? run.state : run.endWord).foregroundStyle(color(run))
                        .frame(width: skin.size.s90, alignment: .trailing)
                    Text(Fmt.age((run.endedAt ?? Date()).timeIntervalSince(run.startedAt ?? run.queuedAt)))
                        .frame(width: skin.size.s40, alignment: .trailing)
                    Text("\(Fmt.tokens(run.tokens)) tok").frame(width: skin.size.s70, alignment: .trailing)
                    Text(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "unpriced")
                        .frame(width: skin.size.s70, alignment: .trailing)
                }
                .citadelFont("t12", mono: true)
                .foregroundStyle(skin.color(skin.text.muted))
            })
    }

    /// "Mira · run #418 · started 11:14 · runner lost".
    private func subtitle(_ run: RunInfo, agent: AgentInfo?) -> String {
        var parts = [agent?.name ?? "Agent", "run #\(run.id)"]
        parts.append("started \((run.startedAt ?? run.queuedAt).formatted(date: .abbreviated, time: .shortened))")
        if !run.isLive, run.state != "succeeded", let reason = run.terminalReason, !reason.isEmpty {
            parts.append(reason)
        }
        return parts.joined(separator: " · ")
    }

    private func color(_ run: RunInfo) -> Color {
        if run.isLive { return theme.accentSecondary }
        switch run.endWord {
        case "succeeded": return status.success
        case "failed", "runner lost", "timed out": return status.danger
        case "cap hit": return status.warning
        default: return skin.color(skin.text.faint)
        }
    }
}
