import AinkradAppKit
import SwiftUI

/// One agent in a team: figure, name, role, and harness · model · what it's on now. Hover for 400 ms shows the
/// hover card; click opens the agent (screen 04); right-click has Open and Copy id.
struct AgentRow: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    let seat: SeatInfo
    @State private var hovering = false
    @State private var showsCard = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let line = model.orgLine(agent)
        HStack(spacing: skin.size.s9) {
            AgentFigure(agent: agent, model: model, size: skin.size.s24, isActive: hovering)
            VStack(alignment: .leading, spacing: skin.size.s1) {
                HStack(alignment: .firstTextBaseline, spacing: skin.size.s4) {
                    Text(agent.name).citadelFont("t13", weight: "medium").foregroundStyle(skin.color(skin.text.primary))
                    Text(role.uppercased()).citadelFont("t9_5", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.faint))
                    if agent.isHirePending {
                        Text("hire pending").citadelFont("t9_5", weight: "semibold").foregroundStyle(status.warning)
                    }
                }
                Text(line.text).citadelFont("t11").lineLimit(1)
                    .foregroundStyle(color(line.tone))
                    .contentTransition(.opacity)
                    .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: line.text)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s8)
        .padding(.vertical, skin.size.s6)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous)
                .fill(skin.color(skin.palette.white).opacity(hovering ? skin.opacity.o05 : 0))
        )
        .opacity(agent.isHirePending ? skin.opacity.o60 : 1)
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .task(id: hovering) {
            guard hovering else {
                showsCard = false
                return
            }
            try? await Task.sleep(for: .milliseconds(400))
            if !Task.isCancelled { showsCard = true }
        }
        .onTapGesture { store.open(.agent(agent.id)) }
        .ainkradContextMenu(OrgMenu.items(agent) { store.open(.agent(agent.id)) })
        .ainkradPopover(isPresented: $showsCard) { AgentHoverCard(store: store, model: model, agent: agent) }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private var role: String {
        switch seat.teamRole {
        case "product_owner": "PO"
        case "team_lead": "Lead"
        default: agent.role
        }
    }

    private func color(_ tone: NeedsItem.Tone?) -> Color {
        switch tone {
        case .warning: status.warning
        case .danger: status.danger
        default: skin.color(skin.text.faint)
        }
    }
}

/// The hover card: current run, today's runs and spend, month budget, runner tags; Open run / Chat / Pause.
struct AgentHoverCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let run = model.currentRun(of: agent.id)
        let live = run?.isLive == true ? run : nil
        VStack(alignment: .leading, spacing: skin.size.s8) {
            HStack(spacing: skin.size.s10) {
                AgentFigure(agent: agent, model: model, size: skin.size.s32)
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    Text(agent.name).citadelFont("t13", weight: "semibold")
                    Text("\(agent.harnessName)\(run?.harnessVersion.map { " \($0)" } ?? "") · \(agent.model)")
                        .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                }
            }
            VStack(spacing: skin.size.s4) {
                if let live {
                    let cap =
                        model.runCap.map { " · \(Int(Double(live.tokens) / Double(max($0, 1)) * 100))% of cap" } ?? ""
                    AinkradStatRow(
                        label: "Now",
                        value:
                            "\(model.issue(live.issueID)?.key ?? "run #\(live.id)") · \(Fmt.age(Date().timeIntervalSince(live.startedAt ?? live.queuedAt)))\(cap)"
                    ).sentenceCaseLabel()
                }
                if let budget = model.budgets.first(where: { $0.scope == "agent:\(agent.id)" && $0.period == "month" })
                {
                    AinkradStatRow(
                        label: "Month budget", value: "\(Fmt.tokens(budget.spent)) of \(Fmt.tokens(budget.cap)) tok"
                    ).sentenceCaseLabel()
                }
                AinkradStatRow(label: "Runner tags", value: agent.runnerTags.joined(separator: " ")).sentenceCaseLabel()
            }
            HStack(spacing: skin.size.s8) {
                if let live {
                    AinkradButton(title: "Open run", style: .secondary) { store.open(.run(live.id)) }
                        .secondaryAccent().compact().fixedSize()
                }
                AinkradButton(title: "Open agent", style: .ghost) { store.open(.agent(agent.id)) }
                    .borderless().secondaryAccent().compact().fixedSize()
            }
        }
        .frame(width: skin.size.s260)
    }
}
