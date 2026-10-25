import AinkradAppKit
import SwiftUI

/// The peek panel (prototype `org.js` orgPanel, 320): everything to check before opening the profile — now, the
/// week, chain, setup, budget, recent runs — and Open run / Profile / Chat, or Approve / Reject for a hire.
struct OrgPeekPanel: View {
    let store: CitadelStore
    let model: CompanyModel
    let agent: AgentInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        let runs = model.agentRuns[agent.id] ?? []
        let live = model.currentRun(of: agent.id).flatMap { $0.isLive ? $0 : nil }
        VStack(spacing: 0) {
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s14) {
                    top
                    if agent.isHirePending {
                        hireCard
                    } else {
                        nowCard(live, runs: runs)
                        statsAndWeek(model.stats(of: agent.id))
                    }
                    chain
                    setup
                    skills
                    budget
                    if !runs.filter({ !$0.isLive }).isEmpty { recent(runs.filter { !$0.isLive }) }
                }
                .padding(.horizontal, skin.size.s18)
                .padding(.top, skin.size.s18)
                .padding(.bottom, skin.size.s8)
            }
            footer(live)
        }
        .frame(width: skin.size.s320)
        .background(shape.fill(skin.color(.palette("background", skin.opacity.o97))))
        .clipShape(shape)
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o10)), lineWidth: 1))
        .overlay(alignment: .topTrailing) {
            AinkradIconButton(systemName: "xmark", size: skin.size.s26, tooltip: "Close") { model.orgPage.picked = nil }
                .padding(skin.size.s12)
        }
        .shadow(color: skin.color(.palette("black", skin.opacity.o40)), radius: skin.size.s20, x: -skin.size.s12)
        .task(id: agent.id) { store.loadPeek(agent.id) }
    }

    private var top: some View {
        let bucket = OrgBucket(agent)
        return VStack(spacing: skin.size.s3) {
            AgentFigure(agent: agent, model: model, size: skin.size.s80, isActive: true)
            Text(agent.name).citadelFont("t17", weight: "semibold").padding(.top, skin.size.s4)
            (Text(agent.role.uppercased()).font(skin.font(AinkradFontToken(sizeKey: "t9_5", weight: "semibold")))
                .foregroundStyle(skin.color(skin.text.faint)) + Text(" · \(peekTitle)"))
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            HStack(spacing: skin.size.s6) {
                Circle().fill(bucket.tint(skin)).frame(width: skin.size.s7, height: skin.size.s7)
                Text(bucket.label).citadelFont("t11")
            }
            .padding(.horizontal, skin.size.s10).frame(height: skin.size.s24)
            .background(
                skin.color(.palette("foreground", skin.opacity.o06)), in: RoundedRectangle(cornerRadius: skin.size.s7)
            )
            .padding(.top, skin.size.s6)
        }
        .frame(maxWidth: .infinity)
    }

    /// `Head of X` / `Team · ★ team lead` / team name / `Company`.
    private var peekTitle: String {
        if let department = model.headedDepartment(of: agent.id) { return "Head of \(department.name)" }
        if let (_, team) = model.team(of: agent.id) {
            return model.lead(of: team)?.id == agent.id ? "\(team.name) · ★ team lead" : team.name
        }
        return agent.orgRole == "ceo" ? "Company" : "Unseated"
    }

    private func card<Content: View>(violet: Bool = false, @ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        let tint = violet ? skin.color(skin.palette.accentViolet) : skin.color(.palette("foreground", 1))
        return VStack(alignment: .leading, spacing: skin.size.s6) { content() }
            .padding(skin.size.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(tint.opacity(violet ? skin.opacity.o08 : skin.opacity.o05)))
            .overlay(shape.strokeBorder(tint.opacity(violet ? skin.opacity.o35 : skin.opacity.o07), lineWidth: 1))
    }

    private var hireCard: some View {
        let approval = model.hireApproval(of: agent.id)
        return card(violet: true) {
            PeekLabel(text: "Hire request")
            Text(approval.map { model.summary($0).title } ?? "Hire \(agent.name)").citadelFont(
                "t12_5", weight: "medium")
            Text(
                "proposed by \(approval.flatMap { model.agent($0.requestedBy)?.name } ?? "—") · nothing runs until you approve"
            )
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        }
    }

    private func nowCard(_ live: RunInfo?, runs: [RunInfo]) -> some View {
        card {
            PeekLabel(text: "Now")
            if let live {
                let issue = model.issue(live.issueID)
                (Text(issue?.key ?? "run #\(live.id)").foregroundStyle(skin.color(skin.palette.accentSecondary))
                    .font(skin.font(AinkradFontToken(sizeKey: "t11", mono: "family"))) + Text(" \(issue?.title ?? "")"))
                    .citadelFont("t12_5", weight: "medium").lineSpacing(skin.size.s2)
                if let tool = model.toolNow[live.id] {
                    Text("▸ \(tool)").citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                        .lineLimit(1).truncationMode(.middle)
                }
                if let cap = model.runCap {
                    HStack(spacing: skin.size.s10) {
                        MiniBar(fraction: Double(live.tokens) / Double(max(cap, 1)))
                        Text("\(Fmt.tokens(live.tokens)) / \(Fmt.tokens(cap))").citadelFont("t10_5", mono: true)
                            .foregroundStyle(skin.color(skin.text.faint))
                    }
                }
            } else {
                Text(model.orgLine(agent).text.components(separatedBy: " · ").last ?? "idle").citadelFont(
                    "t12_5", weight: "medium")
                let last = runs.first { !$0.isLive }
                Group {
                    if let last {
                        Text(
                            "last run #\(last.id) on \(model.issue(last.issueID)?.key ?? "—") · \(Fmt.age(Date().timeIntervalSince(last.endedAt ?? last.queuedAt))) ago"
                        )
                    } else {
                        Text("no runs yet")
                    }
                }
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
        }
    }

    private func statsAndWeek(_ stats: AgentStats) -> some View {
        VStack(spacing: skin.size.s14) {
            HStack(spacing: skin.size.s6) {
                stat("\(stats.weekTotal)", "runs this week")
                stat(stats.successPercent.map { "\($0)%" } ?? "—", "succeeded")
                stat(stats.averageMicros.map { Fmt.dollars(micros: $0) } ?? "—", "avg / run")
            }
            WeekBars(counts: stats.week).padding(.horizontal, skin.size.s4)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: skin.size.s2) {
            Text(value).citadelFont("t16", weight: "semibold")
            Text(label).citadelFont("t10").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
        }
        .padding(.vertical, skin.size.s10).padding(.horizontal, skin.size.s4)
        .frame(maxWidth: .infinity)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s10))
    }

    private var chain: some View {
        let reports = model.reports(of: agent.id)
        return VStack(alignment: .leading, spacing: skin.size.s6) {
            PeekLabel(text: "Chain")
            if let boss = model.agent(agent.reportsTo) {
                AinkradTapArea {
                    model.orgPage.picked = boss.id
                } label: {
                    HStack(spacing: skin.size.s10) {
                        AgentFigure(agent: boss, model: model, size: skin.size.s26)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(boss.name).citadelFont("t12_5", weight: "semibold")
                            Text("reports to · \(boss.role)").citadelFont("t11").foregroundStyle(
                                skin.color(skin.text.faint))
                        }
                        Spacer(minLength: 0)
                    }
                    .padding(.vertical, skin.size.s6).padding(.horizontal, skin.size.s8)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .agentHoverCard(store, model, boss)
                .padding(.horizontal, -skin.size.s8)
            } else {
                Text("Top of the company — reports to you").citadelFont("t11").foregroundStyle(
                    skin.color(skin.text.faint))
            }
            if !reports.isEmpty {
                HStack(spacing: skin.size.s14) {
                    Faces(model: model, ids: reports.prefix(7).map(\.id), size: skin.size.s22)
                    Text(Wording.count(reports.count, "direct report")).citadelFont("t11").foregroundStyle(
                        skin.color(skin.text.faint))
                }
                .help(reports.map(\.name).joined(separator: ", "))
            }
        }
    }

    private var setup: some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            PeekLabel(text: "Setup")
            Grid(alignment: .leading, horizontalSpacing: skin.size.s12, verticalSpacing: skin.size.s7) {
                kv("Harness", "\(agent.harnessName) · \(agent.model)")
                kv("Runners", agent.runnerTags.isEmpty ? "any" : agent.runnerTags.joined(separator: ", "))
                kv(
                    "Hired",
                    agent.isHirePending
                        ? "awaiting approval"
                        : agent.hiredAt.map { $0.formatted(.dateTime.month(.abbreviated).day()) } ?? "—")
            }
        }
    }

    private func kv(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(skin.color(skin.text.faint))
            Text(value).fontWeight(.medium).lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .citadelFont("t12")
    }

    @ViewBuilder private var skills: some View {
        if let skills = model.orgPage.agentSkills[agent.id], !skills.isEmpty {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                PeekLabel(text: "Skills")
                AinkradFlowLayout(spacing: skin.size.s4, lineSpacing: skin.size.s4) {
                    ForEach(skills) { skill in
                        Text(skill.name).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.muted))
                            .padding(.horizontal, skin.size.s7).frame(height: skin.size.s22)
                            .background(
                                skin.color(.palette("foreground", skin.opacity.o06)),
                                in: RoundedRectangle(cornerRadius: skin.size.s6))
                    }
                }
            }
        }
    }

    @ViewBuilder private var budget: some View {
        let budget = model.monthBudget(of: agent.id)
        let stats = model.stats(of: agent.id)
        VStack(alignment: .leading, spacing: skin.size.s6) {
            HStack {
                PeekLabel(text: "Month budget")
                Spacer()
                Text(budget?.pairWord ?? "no budget")
                    .citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.muted))
            }
            MiniBar(fraction: agent.isHirePending ? 0 : budget?.fraction ?? 0, warnAt: budget?.warnFraction ?? 0.8)
            Text(
                agent.isHirePending
                    ? "starts once hired"
                    : "today \(Wording.count(stats.todayRuns, "run")) · \(Fmt.dollars(micros: stats.todayMicros))"
            )
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        }
    }

    private func recent(_ runs: [RunInfo]) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            PeekLabel(text: "Recent runs").padding(.bottom, skin.size.s6)
            ForEach(runs.prefix(3)) { run in
                AinkradTapArea {
                    store.open(.run(run.id))
                } label: {
                    HStack(spacing: skin.size.s8) {
                        Text(model.issue(run.issueID)?.key ?? "#\(run.id)").citadelFont("t11", mono: true)
                            .foregroundStyle(skin.color(skin.palette.accentSecondary))
                        RunStatePill(run: run)
                        Spacer()
                        Text("\(Fmt.age(run.duration)) · \(run.costMicros.map { Fmt.dollars(micros: $0) } ?? "sub")")
                            .citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    }
                    .frame(height: skin.size.s32)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func footer(_ live: RunInfo?) -> some View {
        HStack(spacing: skin.size.s8) {
            if agent.isHirePending, let approval = model.hireApproval(of: agent.id) {
                AinkradDockButton("Approve hire", tone: .primary, height: skin.size.s34, fillsWidth: true) {
                    store.decideHire(approval, approve: true)
                }
                AinkradDockButton("Reject", tone: .danger, height: skin.size.s34, fillsWidth: true) {
                    store.decideHire(approval, approve: false)
                }
            } else {
                if let live {
                    AinkradDockButton("Open run", tone: .primary, height: skin.size.s34, fillsWidth: true) {
                        store.open(.run(live.id))
                    }
                } else {
                    AinkradDockButton("Profile", tone: .primary, height: skin.size.s34, fillsWidth: true) {
                        store.open(.agent(agent.id))
                    }
                }
                AinkradDockButton("Chat", height: skin.size.s34, fillsWidth: true) { store.chat(with: agent.id) }
            }
        }
        .padding(.horizontal, skin.size.s18)
        .padding(.top, skin.size.s12)
        .padding(.bottom, skin.size.s16)
        .background(skin.color(.palette("black", skin.opacity.o15)))
    }
}
