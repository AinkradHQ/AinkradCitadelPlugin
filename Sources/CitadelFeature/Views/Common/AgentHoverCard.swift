import AinkradAppKit
import SwiftUI

/// The agent hover card (spec 01 §1.6, prototype `ui.js` HOVER.agent): figure 48, name, role · team, harness
/// badge and model; Now, Today, Month budget, Runner tags; Open run / Profile / Chat. Shown by `.agentHoverCard`.
struct AgentHoverCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let live = model.currentRun(of: agent.id).flatMap { $0.isLive ? $0 : nil }
        let team = model.team(of: agent.id)?.1
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(alignment: .top, spacing: skin.size.s12) {
                AgentFigure(agent: agent, model: model, size: skin.size.s48, isActive: true)
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text(agent.name).citadelFont("t14", weight: "semibold").foregroundStyle(
                        skin.color(skin.text.primary))
                    Text("\(agent.role)\(team.map { " · \($0.name)" } ?? "")").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                    HStack(spacing: skin.size.s6) {
                        AinkradBadge(text: agent.harnessName, tint: agent.figureHarness?.color ?? theme.foreground)
                        Text(agent.model).citadelFont("t10_5", mono: true).foregroundStyle(
                            skin.color(skin.text.faint))
                    }
                    .padding(.top, skin.size.s2)
                }
            }
            Grid(alignment: .leading, horizontalSpacing: skin.size.s12, verticalSpacing: skin.size.s6) {
                GridRow {
                    label("Now")
                    if let live {
                        (Text(model.issue(live.issueID)?.key ?? "run #\(live.id)").foregroundStyle(
                            theme.accentSecondary)
                            + Text(" · \(Fmt.age(Date().timeIntervalSince(live.startedAt ?? live.queuedAt)))"))
                            .citadelFont("t11", mono: true)
                    } else {
                        StatePill(
                            text: model.orgLine(agent).text.components(separatedBy: " · ").last ?? "idle",
                            tint: tint(OrgBucket(agent)))
                    }
                }
                if let today = today {
                    GridRow {
                        label("Today")
                        value(today)
                    }
                }
                if let budget = model.monthBudget(of: agent.id) {
                    GridRow {
                        label("Month budget")
                        value("\(Fmt.tokens(budget.spent)) of \(Fmt.tokens(budget.cap)) tok")
                    }
                }
                GridRow {
                    label("Runner tags")
                    value(agent.runnerTags.isEmpty ? "any" : agent.runnerTags.joined(separator: ", ")).monospaced()
                }
            }
            HStack(spacing: skin.size.s6) {
                if let live {
                    AinkradButton(title: "Open run", style: .primary) { store.open(.run(live.id)) }.compact()
                        .fixedSize()
                }
                AinkradButton(title: "Profile", style: .secondary) { store.open(.agent(agent.id)) }.compact()
                    .fixedSize()
                AinkradButton(title: "Chat", style: .ghost) { store.chat(with: agent.id) }.borderless().compact()
                    .fixedSize()
            }
        }
        .frame(width: skin.size.s260)
    }

    /// Today's runs and spend, when the agent's runs are loaded (they are on its page and after a hover there).
    private var today: String? {
        guard let runs = model.agentRuns[agent.id] else { return nil }
        let mine = runs.filter { Calendar.current.isDateInToday($0.queuedAt) }
        let cost = mine.compactMap(\.costMicros).reduce(0, +)
        return "\(Wording.count(mine.count, "run")) · \(Fmt.dollars(micros: cost))"
    }

    private func label(_ text: String) -> some View {
        Text(text).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
    }

    private func value(_ text: String) -> Text {
        Text(text).foregroundStyle(skin.color(skin.text.primary))
    }

    private func tint(_ bucket: OrgBucket) -> Color { bucket.tint(skin) }
}

extension OrgBucket {
    /// The bucket's dot: cyan busy, amber waiting, red blocked, slate idle / paused, violet pending.
    func tint(_ skin: AinkradSkin) -> Color {
        switch self {
        case .busy: skin.color(skin.palette.accentSecondary)
        case .warn: skin.color(skin.palette.warning)
        case .bad: skin.color(skin.palette.danger)
        case .idle: skin.color(.palette("foreground", skin.opacity.o50))
        case .away: skin.color(.palette("foreground", skin.opacity.o30))
        case .pending: skin.color(skin.palette.accentViolet)
        }
    }
}

extension View {
    /// The shared agent hover card after a 420 ms rest (kit `ainkradHoverCard`).
    func agentHoverCard(_ store: CitadelStore, _ model: CompanyModel, _ agent: AgentInfo, enabled: Bool = true)
        -> some View
    {
        ainkradHoverCard(isEnabled: enabled) { AgentHoverCard(store: store, model: model, agent: agent) }
    }
}
