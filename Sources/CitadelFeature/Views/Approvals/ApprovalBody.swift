import AinkradAppKit
import SwiftUI

/// The stage's body for one approval kind: sprint KPIs and issues, merge PR cards, the budget gauge and new-cap
/// slider, the hire's agent and setup, the permission's command, policy and scope. Sections rise in, 60 ms apart.
struct ApprovalBody: View {
    let store: CitadelStore
    let model: CompanyModel
    let approval: ApprovalInfo
    @Binding var newCap: Double
    @Binding var scope: AllowScope
    let isPending: Bool
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    private var f: [String: String] { approval.fields }
    private var asker: AgentInfo? { model.agent(approval.requestedBy) }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            ForEach(Array(sections.enumerated()), id: \.offset) { index, section in
                section.riseIn(delay: Double(min(index, 3)) * 0.06)
            }
        }
    }

    private var sections: [AnyView] {
        switch approval.kind {
        case "sprint_commit", "plan_approval": sprint
        case "pr_merge": merge
        case "workflow_push": workflowPush
        case "budget_overrun": budget
        case "hire_agent": hire
        case "permission_escalation": permission
        default: [f["summary"].map { AnyView(QuoteCard(agent: asker, text: $0, model: model)) }].compactMap { $0 }
        }
    }

    // MARK: - Sprint

    private var sprint: [AnyView] {
        let rows = approval.lists["issues"] ?? approval.lists["tasks"] ?? []
        let points = Int(f["points"] ?? "") ?? 0
        let capacity = f["capacity"].flatMap(Int.init)
        let project = model.sprintProject(approval)
        var out: [AnyView] = [AnyView(sprintKPIs(points: points, capacity: capacity, project: project))]
        if !rows.isEmpty {
            out.append(
                AnyView(
                    StageCard(title: Wording.count(rows.count, "issue")) {
                        LazyVGrid(
                            columns: [GridItem(.adaptive(minimum: skin.size.s220), spacing: skin.size.s8)],
                            spacing: skin.size.s8
                        ) {
                            ForEach(Array(rows.enumerated()), id: \.offset) { _, row in issueChip(row) }
                        }
                    }))
        }
        if let goal = f["goal"], !goal.isEmpty {
            out.append(AnyView(QuoteCard(agent: asker, text: "Goal: \(goal)", model: model)))
        }
        if let reason = f["override_reason"], !reason.isEmpty {
            out.append(AnyView(QuoteCard(agent: asker, text: "Over capacity: \(reason)", model: model)))
        }
        return out
    }

    private func sprintKPIs(points: Int, capacity: Int?, project: ProjectInfo?) -> some View {
        let over = capacity.map { points > $0 } ?? false
        let blue = ApprovalFilter.sprint.tint(skin)
        let series = project.flatMap { model.velocitySeries[$0.id] } ?? []
        return HStack(spacing: skin.size.s10) {
            kpi {
                if let capacity, capacity > 0 {
                    let share = Double(points) / Double(capacity)
                    AinkradRingGauge(
                        value: share, tint: over ? skin.color(skin.palette.danger) : blue, diameter: skin.size.s64,
                        lineWidth: skin.size.s6
                    ) {
                        Text("\(Int((share * 100).rounded()))%").citadelFont("t12", weight: "semibold")
                            .foregroundStyle(skin.color(skin.text.primary))
                    }
                }
                kpiText(
                    value: "\(points)", unit: capacity.map { "/ \($0) pts" } ?? "pts",
                    label: capacity.map {
                        over ? "capacity · \(points - $0) pts over" : "capacity · \($0 - points) pts spare"
                    } ?? "no team capacity set")
            }
            kpi {
                kpiText(
                    value: project.flatMap { model.velocity[$0.id] }.map { "\(Int($0.rounded()))" } ?? "—",
                    unit: "avg", label: "velocity · last \(max(series.count, 3))")
                Spacer(minLength: 0)
                if series.count > 1 { Sparkline(values: series.map(Double.init), tint: blue) }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    private func kpi<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: skin.size.s14) { content() }
            .padding(skin.size.s14)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                skin.color(.palette("foreground", skin.opacity.o03)), in: RoundedRectangle(cornerRadius: skin.size.s16))
    }

    private func kpiText(value: String, unit: String, label: String) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s2) {
            HStack(alignment: .firstTextBaseline, spacing: skin.size.s4) {
                Text(value).citadelFont("t20", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                Text(unit).citadelFont("t12", weight: "medium").foregroundStyle(skin.color(skin.text.faint))
            }
            Text(label).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        }
    }

    private func issueChip(_ row: [String: String]) -> some View {
        HStack(spacing: skin.size.s8) {
            Text(row["key"] ?? "").citadelFont("t11", mono: true).foregroundStyle(theme.accentSecondary)
            Text(row["title"] ?? "").citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
            Spacer(minLength: skin.size.s4)
            Text(row["points"] ?? "–").citadelFont("t11", weight: "semibold", mono: true)
                .foregroundStyle(skin.color(skin.text.muted))
        }
        .padding(.horizontal, skin.size.s10)
        .padding(.vertical, skin.size.s8)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s12).strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o06))))
    }

    // MARK: - Merge

    private var merge: [AnyView] {
        let prs = approval.lists["prs"] ?? []
        let green = skin.color(skin.palette.success)
        var out: [AnyView] = [
            AnyView(
                HStack(spacing: skin.size.s10) {
                    ForEach(Array(prs.enumerated()), id: \.offset) { index, pr in
                        if index > 0 {
                            VStack(spacing: skin.size.s2) {
                                Image(systemName: "arrow.right").citadelFont("t15")
                                Text("then").citadelFont("t10")
                            }
                            .foregroundStyle(skin.color(skin.text.faint))
                        }
                        MergePRCard(model: model, approval: approval, row: pr, order: index + 1)
                    }
                })
        ]
        if let notes = f["qa_notes"], !notes.isEmpty {
            out.append(AnyView(QuoteCard(agent: asker, text: notes, model: model)))
        }
        let first = prs.first?["repo"]
        let checks = prs.compactMap { $0["checks_note"] }.filter { !$0.isEmpty }
        out.append(
            AnyView(
                InfoTileGrid(tiles: [
                    InfoTile(
                        systemImage: "arrow.triangle.branch", tint: green, label: "Merge order",
                        value: "project repo order\(first.map { " · \($0) first" } ?? "")"),
                    InfoTile(
                        systemImage: "checkmark.circle", tint: green, label: "Done when",
                        value: "every PR merged · the issue closes"),
                    InfoTile(
                        systemImage: "checkmark.seal", tint: green, label: "Checks",
                        value: checks.isEmpty ? "passed" : checks.joined(separator: " · ")),
                    InfoTile(
                        systemImage: "person.crop.circle.badge.checkmark", tint: green, label: "Verified by",
                        value: asker?.nameAndRole ?? "QA"),
                ])))
        return out
    }

    // MARK: - Workflow push (plugin-only, API minor 15)

    private var workflowPush: [AnyView] {
        let files = (f["files"] ?? "").split(separator: " ").map(String.init)
        let tint = skin.color(skin.palette.warning)
        var out: [AnyView] = [
            AnyView(
                InfoTileGrid(tiles: [
                    InfoTile(systemImage: "shippingbox", tint: tint, label: "Repo", value: f["repo"] ?? "—"),
                    InfoTile(
                        systemImage: "arrow.triangle.branch", tint: tint, label: "Branch", value: f["branch"] ?? "—"),
                    InfoTile(
                        systemImage: "number", tint: tint, label: "Head",
                        value: f["sha"].map { String($0.prefix(12)) } ?? "—"),
                    InfoTile(systemImage: "play", tint: tint, label: "Run", value: f["run"].map { "#\($0)" } ?? "—"),
                ]))
        ]
        if !files.isEmpty {
            out.append(
                AnyView(
                    StageCard(title: Wording.count(files.count, "workflow file")) {
                        VStack(alignment: .leading, spacing: skin.size.s4) {
                            ForEach(files, id: \.self) { file in
                                Text(file).citadelFont("t11", mono: true)
                                    .foregroundStyle(skin.color(skin.text.primary))
                            }
                        }
                    }))
        }
        if let rejection = f["rejection"], !rejection.isEmpty {
            out.append(AnyView(QuoteCard(agent: nil, text: "The forge refused: \(rejection)", model: model)))
        }
        if let branch = f["branch"] {
            out.append(AnyView(TerminalCard(title: "push it yourself", command: "git push origin \(branch):\(branch)")))
        }
        return out
    }

    // MARK: - Budget (tokens: the server keeps no dollar caps)

    private var budget: [AnyView] {
        guard let numbers = BudgetNumbers(f) else {
            return [f["summary"].map { AnyView(QuoteCard(agent: nil, text: $0, model: model)) }].compactMap { $0 }
        }
        let scale = Double(numbers.cap) * 2
        let warn = Double(numbers.cap) * model.warnFraction
        let shownCap = Int64((newCap / 1000).rounded()) * 1000
        let what = model.issue(approval.issueID)?.key ?? "\((f["scope"] ?? "budget").capitalizedFirst)"
        let amber = skin.color(skin.palette.warning)
        return [
            AnyView(
                StageCard(
                    title: "\(what) spend", note: "\(Fmt.tokens(numbers.spent)) of \(Fmt.tokens(numbers.cap)) tokens"
                ) {
                    MarkerGauge(
                        fill: Double(numbers.spent) / scale, nowLabel: Fmt.tokens(numbers.spent),
                        ticks: [
                            GaugeTick(fraction: warn / scale, label: "warn \(Fmt.tokens(Int64(warn)))"),
                            GaugeTick(fraction: 0.5, label: "cap \(Fmt.tokens(numbers.cap))", isCap: true),
                        ], marker: newCap / scale)
                }),
            AnyView(
                HStack(spacing: skin.size.s12) {
                    Text("New cap").citadelFont("t12").foregroundStyle(skin.color(skin.text.primary))
                    AinkradSlider(value: $newCap, in: Double(numbers.cap)...scale)
                    Text(Fmt.tokens(shownCap)).citadelFont("t16", weight: "bold", mono: true)
                        .foregroundStyle(amber)
                        .frame(minWidth: skin.size.s64, alignment: .trailing)
                }
                .padding(.horizontal, skin.size.s14)
                .padding(.vertical, skin.size.s12)
                .background(amber.opacity(skin.opacity.o06), in: RoundedRectangle(cornerRadius: skin.size.s14))
                .overlay(RoundedRectangle(cornerRadius: skin.size.s14).strokeBorder(amber.opacity(skin.opacity.o20)))
                .disabled(!isPending)),
        ]
    }

    // MARK: - Hire

    private var hire: [AnyView] {
        let violet = skin.color(skin.palette.accentViolet)
        let hired = model.agent(approval.agentID)
        let role = (f["role"] ?? hired?.role ?? "agent").capitalizedFirst
        let line = [role, model.teamPath(of: approval.agentID), "resting until hired"].compactMap { $0 }
            .joined(separator: " · ")
        var tiles = [
            InfoTile(
                systemImage: "server.rack", tint: violet, label: "Harness · model",
                value: "\(AgentLook.harnessName(f["harness"] ?? "")) · \(f["model"] ?? "—")"),
            InfoTile(
                systemImage: "person.text.rectangle", tint: violet, label: "Org role",
                value: f["org_role"].flatMap { $0 == "none" ? nil : $0.uppercased() } ?? "member"),
        ]
        if let tags = f["runner_tags"], !tags.isEmpty {
            tiles.append(InfoTile(systemImage: "tag", tint: violet, label: "Runner tags", value: tags))
        }
        if let boss = model.agent(hired?.reportsTo) {
            tiles.append(
                InfoTile(systemImage: "arrow.up.right", tint: violet, label: "Reports to", value: boss.nameAndRole))
        }
        var out: [AnyView] = [
            AnyView(
                HStack(spacing: skin.size.s18) {
                    if let hired { AgentFigure(agent: hired, model: model, size: skin.size.s96) }
                    VStack(alignment: .leading, spacing: skin.size.s4) {
                        Text(f["name"] ?? hired?.name ?? "New agent").citadelFont("t18", weight: "bold")
                            .foregroundStyle(skin.color(skin.text.primary))
                        Text(line).citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                    }
                    Spacer(minLength: 0)
                }
                .padding(skin.size.s18)
                .background(
                    RoundedRectangle(cornerRadius: skin.size.s18).fill(
                        RadialGradient(
                            colors: [
                                violet.opacity(skin.opacity.o18), skin.color(.palette("foreground", skin.opacity.o03)),
                            ],
                            center: .leading, startRadius: 0, endRadius: skin.size.s640)))),
            AnyView(InfoTileGrid(tiles: tiles)),
        ]
        if let why = f["justification"], !why.isEmpty {
            out.append(AnyView(QuoteCard(agent: asker, text: why, model: model)))
        }
        return out
    }

    // MARK: - Permission

    private var permission: [AnyView] {
        let ask = PermissionAsk(f)
        let run = f["run"].flatMap(Int64.init)
        let runner = run.flatMap { model.runs[$0]?.runnerID }.flatMap { model.runners[$0] }
        let title = [asker?.name, run.map { "run #\($0)" }, runner].compactMap { $0 }.joined(separator: " · ")
        let issue = model.issue(approval.issueID)
        let policy = issue.flatMap { model.projectsPage.policies[$0.projectID] }
        return [
            AnyView(TerminalCard(title: title, command: ask.command.isEmpty ? ask.tool : ask.command)),
            AnyView(
                HStack(spacing: skin.size.s10) {
                    policyBox("Policy now", policy.map(Self.policyLine) ?? "the project's policy", isAsk: false)
                    Image(systemName: "arrow.right").citadelFont("t13").foregroundStyle(skin.color(skin.text.faint))
                        .frame(width: skin.size.s38, height: skin.size.s38)
                        .background(
                            skin.color(.palette("foreground", skin.opacity.o03)),
                            in: RoundedRectangle(cornerRadius: skin.size.s10))
                    policyBox("Asks for", ask.rule.replacingOccurrences(of: ":", with: ": "), isAsk: true)
                }
                .fixedSize(horizontal: false, vertical: true)),
            AnyView(
                StageCard(title: "Allow for") {
                    HStack(spacing: skin.size.s6) {
                        scopeCard(.once, "Once", "just this command", enabled: true)
                        scopeCard(
                            .issue, "This issue", "\(issue?.key ?? "no issue") · same command", enabled: issue != nil)
                        scopeCard(.project, "This project", "saved as a rule", enabled: issue != nil)
                    }
                    .fixedSize(horizontal: false, vertical: true)
                }),
        ]
    }

    private func policyBox(_ label: String, _ value: String, isAsk: Bool) -> some View {
        let amber = skin.color(skin.palette.warning)
        return VStack(alignment: .leading, spacing: skin.size.s3) {
            Text(label.uppercased()).citadelFont("t10_5").tracking(skin.size.s1 / 2)
                .foregroundStyle(skin.color(skin.text.faint))
            Text(value).citadelFont("t12_5").foregroundStyle(isAsk ? amber : skin.color(skin.text.primary))
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.vertical, skin.size.s12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)), in: RoundedRectangle(cornerRadius: skin.size.s14)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s14).strokeBorder(isAsk ? amber.opacity(skin.opacity.o30) : .clear)
        )
    }

    private func scopeCard(_ option: AllowScope, _ title: String, _ detail: String, enabled: Bool) -> some View {
        let amber = skin.color(skin.palette.warning)
        let isOn = scope == option
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        return AinkradTapArea(action: { if enabled && isPending { scope = option } }) {
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(title).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary))
                Text(detail).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
            }
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s10)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .background(
                shape.fill(
                    isOn ? amber.opacity(skin.opacity.o10) : skin.color(.palette("foreground", skin.opacity.o03)))
            )
            .overlay(
                shape.strokeBorder(
                    isOn ? amber.opacity(skin.opacity.o45) : skin.color(.palette("foreground", skin.opacity.o06)))
            )
            .contentShape(shape)
            .opacity(enabled ? 1 : skin.opacity.o45)
        }
    }

    /// "ask", "accept_edits", "sandboxed" in words, with the allowlist's size.
    static func policyLine(_ policy: PolicyInfo) -> String {
        let mode =
            switch policy.mode {
            case "ask": "asks for every call"
            case "accept_edits": "edits allowed, asks for the rest"
            case "sandboxed": "sandboxed"
            default: policy.mode.replacingOccurrences(of: "_", with: " ")
            }
        let sandbox = policy.sandboxed && policy.mode != "sandboxed" ? ", sandboxed" : ""
        return "\(mode)\(sandbox) · \(Wording.count(policy.allow.count, "rule"))"
    }
}
