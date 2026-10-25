import AinkradAppKit
import SwiftUI

/// Home's right column: requirement donuts, the team, recent activity, today's spend.
struct RequirementsTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    private var open: [RequirementInfo] {
        model.requirements.filter { $0.state != "done" && $0.state != "cancelled" }
            .sorted { ($0.state == "plan_review" ? 0 : 1, -$0.id) < ($1.state == "plan_review" ? 0 : 1, -$1.id) }
    }

    var body: some View {
        AinkradBentoTile {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                AinkradSectionHead(title: "Requirements", count: "\(open.count)", link: "All →") {
                    store.screen = .requirements
                }
                ForEach(open.prefix(4), id: \.id) { row($0) }
                if open.isEmpty {
                    AinkradTapArea {
                        store.isComposingRequirement = true
                    } label: {
                        Label("New requirement", systemImage: "plus").citadelFont("t12", weight: "medium")
                            .foregroundStyle(skin.color(skin.palette.accentSecondary))
                    }
                    .buttonStyle(.plain)
                    .padding(.vertical, skin.size.s8)
                }
            }
        }
    }

    private func row(_ requirement: RequirementInfo) -> some View {
        let planning = requirement.state == "plan_review" || requirement.points == 0
        let fraction = requirement.points > 0 ? Double(requirement.donePoints) / Double(requirement.points) : 0
        let asks = model.questions.filter { $0.isOpen && $0.requirementID == requirement.id }.count
        let tint = fraction >= 1 ? status.success : asks > 0 ? status.warning : skin.color(skin.palette.accentSecondary)
        return HStack(spacing: skin.size.s10) {
            AinkradRingGauge(
                value: planning ? nil : fraction, tint: tint, diameter: skin.size.s34, lineWidth: skin.size.s4
            ) {
                Text(planning ? "—" : "\(Int(fraction * 100))%").citadelFont("t9", weight: "semibold", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary))
            }
            VStack(alignment: .leading, spacing: skin.size.s1) {
                HStack(spacing: skin.size.s5) {
                    Text(requirement.key).citadelFont("t11", mono: true).foregroundStyle(
                        skin.color(skin.palette.accentSecondary))
                    Text(requirement.title).citadelFont("t13", weight: "medium").foregroundStyle(
                        skin.color(skin.text.primary)
                    )
                    .lineLimit(1)
                }
                meta(requirement, planning: planning, asks: asks).citadelFont("t11").lineLimit(1)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if asks > 0 {
                Text("\(asks)").citadelFont("t10", weight: "bold", mono: true).foregroundStyle(
                    skin.color(.palette("background", 1))
                )
                .frame(width: skin.size.s18, height: skin.size.s18).background(status.warning, in: Circle())
            } else if requirement.state == "plan_review" {
                AinkradStatePill(text: "plan", tint: status.warning)
            }
        }
        .padding(skin.size.s8)
        .contentShape(Rectangle())
        .onTapGesture {
            model.requirementsPage.selectedID = requirement.id
            store.screen = .requirements
        }
    }

    private func meta(_ requirement: RequirementInfo, planning: Bool, asks: Int) -> Text {
        let faint = skin.color(skin.text.faint)
        if requirement.state == "plan_review" {
            return Text("\(requirement.points) pts · ").foregroundStyle(faint)
                + Text("approve plan to start").foregroundStyle(status.warning)
        }
        var text = Text("\(requirement.donePoints) / \(requirement.points) pts").foregroundStyle(faint)
        if let eta = requirement.eta { text = text + Text(" · ETA \(Fmt.eta(eta))").foregroundStyle(faint) }
        if asks > 0, let owner = model.agent(requirement.ownerAgentID) {
            return text + Text(" · \(owner.name) asks you").foregroundStyle(status.warning)
        }
        if let owner = model.agent(requirement.ownerAgentID) {
            text = text + Text(" · PO \(owner.name)").foregroundStyle(faint)
        }
        return text
    }
}

/// "Team": a stacked state bar with its legend, then every agent's figure.
struct TeamTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let agents = model.agents.values.filter { $0.status != "terminated" }.sorted { $0.id < $1.id }
        let working = agents.filter { [.working, .thinking, .loading].contains($0.figure) }.count
        let needs = agents.filter { [.listening, .confused, .error].contains($0.figure) }.count
        let away = agents.filter { $0.isPaused || $0.isHirePending || $0.figure == .sleepy }.count
        let idle = max(0, agents.count - working - needs - away)
        let parts: [(String, Int, Color)] = [
            ("Working", working, skin.color(skin.palette.accentSecondary)), ("Needs you", needs, status.warning),
            ("Idle", idle, skin.color(skin.text.muted)), ("Away", away, skin.color(skin.text.faint)),
        ]
        AinkradBentoTile {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                AinkradSectionHead(title: "Team", count: "\(agents.count)", link: "Org →") { store.screen = .org }
                GeometryReader { geo in
                    HStack(spacing: skin.size.s2) {
                        ForEach(parts.filter { $0.1 > 0 }, id: \.0) { part in
                            RoundedRectangle(cornerRadius: skin.size.s4).fill(part.2)
                                .frame(
                                    width: max(
                                        0, geo.size.width * Double(part.1) / Double(max(agents.count, 1)) - skin.size.s2
                                    ))
                        }
                    }
                }
                .frame(height: skin.size.s8)
                Grid(alignment: .leading, horizontalSpacing: skin.size.s16, verticalSpacing: skin.size.s4) {
                    GridRow {
                        legend(parts[0])
                        legend(parts[1])
                    }
                    GridRow {
                        legend(parts[2])
                        legend(parts[3])
                    }
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: skin.size.s30), spacing: skin.size.s8)], spacing: skin.size.s8
                ) {
                    ForEach(agents) { agent in
                        AinkradTapArea {
                            store.open(.agent(agent.id))
                        } label: {
                            AgentFigure(agent: agent, model: model, size: skin.size.s30)
                                .opacity(agent.isPaused || agent.isHirePending ? skin.opacity.o55 : 1)
                        }
                        .buttonStyle(.plain)
                        .help("\(agent.name) · \(agent.role)")
                    }
                }
            }
        }
    }

    private func legend(_ part: (String, Int, Color)) -> some View {
        HStack(spacing: skin.size.s6) {
            Circle().fill(part.2).frame(width: skin.size.s7, height: skin.size.s7)
            Text(part.0).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            Text("\(part.1)").citadelFont("t12", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
        }
    }
}

/// "Recent activity": the last answered approvals and ended runs on a timeline.
struct ActivityTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    private struct Event: Identifiable {
        let id: String
        let glyph: String
        let tint: Color
        let title: String
        let detail: String
        let at: Date
        let open: () -> Void
    }

    private var events: [Event] {
        var events = model.answeredApprovals.prefix(2).map { approval in
            Event(
                id: "a\(approval.id)", glyph: approval.status == "approved" ? "✓" : "✕",
                tint: approval.status == "approved" ? status.success : status.danger,
                title: model.summary(approval).title,
                detail: "\(approval.status) by you", at: approval.decidedAt ?? .distantPast
            ) {
                store.selectedApproval = approval.id
                store.screen = .approvals
            }
        }
        let ended = (model.companyRuns ?? []).filter { !$0.isLive && $0.endedAt != nil }.prefix(4)
        events += ended.map { run in
            let ok = run.state == "succeeded"
            let who = model.agent(run.agentID)?.name ?? "Agent"
            let key = model.issue(run.issueID).map { " · \($0.key)" } ?? ""
            return Event(
                id: "r\(run.id)", glyph: ok ? "▶" : "⚑",
                tint: ok ? skin.color(skin.palette.accentSecondary) : status.danger,
                title: "\(who)\(key)", detail: "run #\(run.id) \(run.endWord)", at: run.endedAt ?? run.queuedAt
            ) { store.open(.run(run.id)) }
        }
        return Array(events.sorted { $0.at > $1.at }.prefix(5))
    }

    var body: some View {
        AinkradBentoTile {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                AinkradSectionHead(title: "Recent activity", link: "Runs →") { store.screen = .runs }
                if events.isEmpty {
                    Text("Nothing has happened yet today.").citadelFont("t12").foregroundStyle(
                        skin.color(skin.text.faint))
                }
                VStack(alignment: .leading, spacing: skin.size.s4) {
                    ForEach(events) { event in
                        HStack(spacing: skin.size.s10) {
                            AinkradIconTile(glyph: event.glyph, tint: event.tint)
                            VStack(alignment: .leading, spacing: skin.size.s1) {
                                Text(event.title).citadelFont("t12_5", weight: "medium")
                                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                                Text(event.detail).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                                    .lineLimit(1)
                            }
                            Spacer(minLength: skin.size.s6)
                            Text(event.at.formatted(date: .omitted, time: .shortened)).citadelFont("t10", mono: true)
                                .foregroundStyle(skin.color(skin.text.faint))
                        }
                        .contentShape(Rectangle())
                        .onTapGesture(perform: event.open)
                    }
                }
                .background(alignment: .leading) {
                    LinearGradient(
                        colors: [skin.color(.palette("foreground", skin.opacity.o12)), .clear], startPoint: .top,
                        endPoint: .bottom
                    )
                    .frame(width: skin.size.s2)
                    .padding(.leading, skin.size.s14)
                }
            }
        }
    }
}

/// "Spend today": the hourly line, priced / unpriced / subscription, and the budgets nearest their line.
struct SpendTile: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradBentoTile {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                AinkradSectionHead(title: "Spend today", link: "Cost →") { store.screen = .cost }
                AinkradLineChart(
                    title: "Spend today",
                    series: [
                        AinkradChartSeries(
                            name: "Spend", points: cumulative.map { AinkradChartPoint(x: $0.0, y: $0.1) },
                            tone: .accentSecondary)
                    ],
                    fillsArea: true, emptyMessage: "No spend yet today"
                )
                .frame(height: skin.size.s80 + skin.size.s4)
                if let spend = model.spend {
                    SpendSplitBar(spend: spend)
                    Text(
                        "Priced \(Fmt.dollars(micros: model.spendToday?.costMicros ?? 0)) · Unpriced \(Wording.count(Int(model.spendToday?.unpricedRuns ?? 0), "run")) · Subscription \(Fmt.tokens(spend.subscriptionTokens)) tok"
                    )
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                }
                Text("Budgets near the line").citadelFont("t10_5", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.muted)).padding(.top, skin.size.s4)
                ForEach(model.budgets.sorted { $0.fraction > $1.fraction }.prefix(3)) { budget in
                    HStack(spacing: skin.size.s12) {
                        Text("\(budget.label) · \(budget.period)").citadelFont("t12")
                            .foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
                        Spacer(minLength: skin.size.s8)
                        AinkradBudgetBar(
                            label: budget.label, value: Double(budget.shownSpent), limit: Double(budget.shownCap),
                            warnFraction: budget.warnFraction, showsHardLimit: false
                        )
                        .frame(width: skin.size.s120)
                    }
                    .contentShape(Rectangle())
                    .onTapGesture { store.screen = .cost }
                }
                if model.budgets.isEmpty {
                    Text("No budgets set").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                }
            }
        }
    }

    /// Dollars spent so far by hour of the day.
    private var cumulative: [(Double, Double)] {
        var total = 0.0
        return model.hourSpend.map { bucket in
            total += Double(bucket.totals.costMicros) / 1_000_000
            return (Double(Calendar.current.component(.hour, from: bucket.day)), total)
        }
    }
}
