import AinkradAppKit
import SwiftUI

/// One approval: icon + type label, title, who asked; the body for its kind; then the reply and the decision.
/// Every decision can carry the reply (it goes back to the asker and wakes it); "Reply only" sends it without
/// deciding, as a comment on the approval's issue.
struct ApprovalDetail: View {
    let store: CitadelStore
    let model: CompanyModel
    let approval: ApprovalInfo
    @State private var reply = ""
    @State private var newCap = ""
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    private var isPending: Bool { approval.status == "pending" }
    private var f: [String: String] { approval.fields }

    var body: some View {
        let summary = model.summary(approval)
        VStack(alignment: .leading, spacing: 0) {
            head(summary)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s12) { content }
                    .padding(.horizontal, skin.size.s22)
                    .padding(.bottom, skin.size.s14)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            if isPending { decision } else { answered }
        }
    }

    // MARK: - Head

    private func head(_ summary: ApprovalSummary) -> some View {
        HStack(alignment: .top, spacing: skin.size.s12) {
            TypeGlyph(glyph: summary.glyph, tone: summary.tone, isLarge: true)
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(skin.labelCased(summary.typeLabel)).citadelFont("t10", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.muted))
                Text(summary.title).citadelFont("t16", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(2)
                asked.citadelFont("t11").lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s22)
        .padding(.top, skin.size.s18)
        .padding(.bottom, skin.size.s12)
    }

    /// "Mira (PO) asked · CIT-42 · policy: you approve".
    private var asked: Text {
        let muted = skin.color(skin.text.muted)
        var parts: [String] = []
        if let asker = model.agent(approval.requestedBy) { parts.append("\(asker.name) (\(asker.role)) asked") }
        if let key = model.issue(approval.issueID)?.key { parts.append(key) }
        if let expires = approval.expiresAt {
            parts.append("expires \(expires.formatted(date: .omitted, time: .shortened))")
        }
        let base = Text(parts.joined(separator: " · ")).foregroundStyle(muted)
        guard approval.kind == "sprint_commit" else { return base }
        return base + Text(verbatim: " · policy: ").foregroundStyle(muted)
            + Text("you approve").foregroundStyle(skin.color(skin.text.primary)).bold()
    }

    // MARK: - Body by kind

    @ViewBuilder private var content: some View {
        switch approval.kind {
        case "sprint_commit", "plan_approval": sprint
        case "pr_merge": merge
        case "budget_overrun": budget
        case "hire_agent": hire
        case "permission_escalation": permission
        default:
            if let summary = f["summary"] { Quote(who: nil, text: summary) }
        }
    }

    private var sprint: some View {
        let rows = approval.lists["issues"] ?? approval.lists["tasks"] ?? []
        let points = Double(f["points"] ?? "") ?? 0
        let capacity = f["capacity"].flatMap(Double.init)
        let project = rows.first?["key"].flatMap { key in
            model.projects.first { key.hasPrefix("\($0.key)-") }
        }
        return VStack(alignment: .leading, spacing: skin.size.s12) {
            HStack(alignment: .top, spacing: skin.size.s12) {
                Tile(label: "Points", value: f["points"] ?? "—", unit: capacity.map { "/ \(Int($0)) capacity" }) {
                    if let capacity {
                        AinkradBudgetBar(
                            label: "Points", value: points, limit: capacity, warnFraction: nil, showsHardLimit: false,
                            tone: points > capacity ? .warning : .success)
                    }
                }
                Tile(
                    label: "Velocity · last 3",
                    value: project.flatMap { model.velocity[$0.id] }.map { "\(Int($0))" } ?? "—",
                    unit: "avg"
                ) { EmptyView() }
                .onAppear { if let project { store.loadVelocity(project: project.id) } }
            }
            .fixedSize(horizontal: false, vertical: true)
            if !rows.isEmpty {
                AinkradCard {
                    VStack(alignment: .leading, spacing: skin.size.s6) {
                        TileHead(title: "\(rows.count) issues")
                        ForEach(Array(rows.enumerated()), id: \.offset) { _, row in
                            HStack(spacing: skin.size.s12) {
                                Text(row["key"] ?? "").citadelFont("t11", mono: true)
                                    .foregroundStyle(theme.accentSecondary)
                                    .frame(width: skin.size.s70, alignment: .leading)
                                Text(row["title"] ?? "").citadelFont("t12_5", weight: "medium")
                                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                                Spacer(minLength: skin.size.s8)
                                Text(row["points"] ?? "–").citadelFont("t12", mono: true)
                                    .foregroundStyle(skin.color(skin.text.muted))
                            }
                        }
                    }
                }
            }
            if let goal = f["goal"], !goal.isEmpty { Quote(who: "Goal", text: goal) }
            if let reason = f["override_reason"], !reason.isEmpty { Quote(who: "Over capacity", text: reason) }
        }
    }

    private var merge: some View {
        let prs = approval.lists["prs"] ?? []
        return VStack(alignment: .leading, spacing: skin.size.s6) {
            ForEach(Array(prs.enumerated()), id: \.offset) { index, pr in
                HStack(spacing: skin.size.s10) {
                    AinkradBadge(text: pr["repo"] ?? "repo", tint: theme.accentSecondary)
                    Text("PR #\(pr["pr"] ?? "?") · merges \(Self.ordinal(index + 1))").citadelFont("t11", mono: true)
                        .foregroundStyle(skin.color(skin.text.faint))
                    Spacer(minLength: skin.size.s8)
                    if let url = pr["url"].flatMap(URL.init(string:)) {
                        AinkradButton(title: "Open PR", style: .ghost) { NSWorkspace.shared.open(url) }
                            .borderless().secondaryAccent().compact().fixedSize()
                    }
                }
                .padding(skin.size.s10)
                .background(
                    skin.color(skin.palette.white).opacity(skin.opacity.o03),
                    in: RoundedRectangle(cornerRadius: skin.size.s8))
            }
            if let notes = f["qa_notes"], !notes.isEmpty {
                Quote(who: model.agent(approval.requestedBy).map { "\($0.name) (QA)" }, text: notes)
            }
            Text("Merging merges every PR in the project's repo order; the issue is done when all are merged.")
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        }
    }

    private var budgetNumbers: (spent: Int64, cap: Int64)? {
        guard let spent = f["spent"].flatMap(Int64.init), let cap = f["token_cap"].flatMap(Int64.init) else {
            return nil
        }
        return (spent, cap + (f["raised"].flatMap(Int64.init) ?? 0))
    }

    @ViewBuilder private var budget: some View {
        if let (spent, cap) = budgetNumbers {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                AinkradBudgetBar(
                    label: "Budget", value: Double(spent), limit: Double(cap), warnFraction: model.warnFraction,
                    isThick: true)
                Text(
                    "\(Fmt.tokens(spent)) spent · warn \(Int(model.warnFraction * 100))% · cap \(Fmt.tokens(cap)) tokens"
                )
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
            }
            HStack(spacing: skin.size.s12) {
                Text(skin.labelCased("New cap")).citadelFont("t10", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.muted))
                    .frame(width: skin.size.s110, alignment: .leading)
                AinkradTextField(text: $newCap, placeholder: "\(Fmt.tokens(cap * 6 / 5)) tokens").monospaced()
            }
            Text(
                "Approving raises the cap for this period and the blocked runs resume; Stop at cap keeps them stopped."
            )
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        } else if let summary = f["summary"] {
            Quote(who: nil, text: summary)
        }
    }

    private var hire: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            VStack(spacing: skin.size.s4) {
                stat("Harness · model", "\(AgentLook.harnessName(f["harness"] ?? "")) · \(f["model"] ?? "—")")
                stat(
                    "Role",
                    [f["role"], f["org_role"].flatMap { $0 == "none" ? nil : $0.uppercased() }]
                        .compactMap { $0 }.joined(separator: " · "))
                if let tags = f["runner_tags"], !tags.isEmpty { stat("Runner tags", tags) }
            }
            if let why = f["justification"], !why.isEmpty {
                Quote(who: model.agent(approval.requestedBy)?.name, text: why)
            }
        }
    }

    private var permission: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            AinkradCodeBlock(ToolLine.argument(f).isEmpty ? (f["tool"] ?? "") : ToolLine.argument(f))
            VStack(spacing: skin.size.s4) {
                stat("Tool", f["tool"] ?? "—")
                stat("Run", f["run"].map { "#\($0) · waiting" } ?? "—")
                stat("Scope options", "once")
            }
        }
    }

    private func stat(_ label: String, _ value: String) -> some View {
        AinkradStatRow(label: label, value: value).sentenceCaseLabel()
    }

    // MARK: - Decision

    private var replyWakes: String { "Reply wakes \(model.replyTarget(approval))" }

    private var decision: some View {
        VStack(alignment: .leading, spacing: skin.size.s8) {
            AinkradTextField(
                text: $reply,
                placeholder:
                    "Reply to \(model.replyTarget(approval)) — sent with your decision, or alone with “Reply only”")
            HStack(spacing: skin.size.s8) {
                Text(replyWakes).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                Spacer(minLength: skin.size.s8)
                buttons
            }
        }
        .padding(skin.size.s12)
        .background(theme.surface.opacity(skin.opacity.o35), in: RoundedRectangle(cornerRadius: skin.size.s10))
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.size.s14)
        .background {
            // ⌘↵ approves.
            Button("", action: approve)  // design-lint: allow raw-control hidden ⌘↵ claim
                .keyboardShortcut(.return, modifiers: .command).hidden()
        }
    }

    @ViewBuilder private var buttons: some View {
        AinkradButton(title: "Reply only", style: .ghost) {
            store.replyOnly(approval, text: reply)
            reply = ""
        }
        .borderless().secondaryAccent().compact().fixedSize()
        .disabled(approval.issueID == nil || reply.trimmingCharacters(in: .whitespaces).isEmpty)
        .ainkradTooltip(approval.issueID == nil ? "This approval has no issue to reply on" : "Sends the reply alone")
        switch approval.kind {
        case "pr_merge":
            reject("Request changes")
            primary("Merge \((approval.lists["prs"]?.count ?? 1) > 1 ? "all" : "")")
        case "budget_overrun":
            reject("Stop at cap")
            primary(raise.map { "Raise by \(Fmt.tokens($0))" } ?? "Raise")
                .disabled(raise == nil)
        case "hire_agent":
            reject("Reject")
            primary("Hire")
        case "permission_escalation":
            if let run = f["run"].flatMap(Int64.init) {
                AinkradButton(title: "Open run", style: .ghost) { store.open(.run(run)) }
                    .borderless().secondaryAccent().compact().fixedSize()
            }
            reject("Deny")
            AinkradButton(title: "For \(model.issue(approval.issueID)?.key ?? "issue")", style: .secondary) {
                store.allowForIssue(approval, reply: reply)
            }
            .compact().fixedSize().disabled(approval.issueID == nil)
            .ainkradTooltip("Allow this call on the issue's runs for a while, without asking again")
            primary("Allow once")
        default:
            reject("Reject")
            primary("Approve ⌘↵")
        }
    }

    /// The overrun's raise: the typed new cap less the current one, in tokens ("240k", "1.2M", "300000").
    private var raise: Int64? {
        guard let cap = budgetNumbers?.cap, let typed = Self.tokens(newCap), typed > cap else { return nil }
        return typed - cap
    }

    private func reject(_ title: String) -> some View {
        AinkradButton(title: title, style: .danger) {
            store.decide(approval, approve: false, reply: reply)
        }
        .outlined().tintedFill().compact().fixedSize()
    }

    private func primary(_ title: String) -> some View {
        AinkradButton(title: title.trimmingCharacters(in: .whitespaces), style: .primary, action: approve)
            .compact().fixedSize()
    }

    private func approve() {
        guard isPending else { return }
        if approval.kind == "budget_overrun" {
            guard let raise else { return }
            store.decide(approval, approve: true, raiseTokens: raise, reply: reply)
        } else {
            store.decide(approval, approve: true, reply: reply)
        }
    }

    private var answered: some View {
        HStack(spacing: skin.size.s8) {
            AinkradBadge(text: approval.status, status: approval.status == "approved" ? .success : .danger)
            if let reply = approval.reply { Text("You: \(reply)").citadelFont("t12").lineLimit(2) }
            Spacer(minLength: 0)
        }
        .foregroundStyle(skin.color(skin.text.muted))
        .padding(skin.size.s16)
    }

    static func ordinal(_ n: Int) -> String {
        switch n {
        case 1: "1st"
        case 2: "2nd"
        case 3: "3rd"
        default: "\(n)th"
        }
    }

    /// "240k" → 240 000, "1.2M" → 1 200 000, "300000" → 300 000.
    static func tokens(_ text: String) -> Int64? {
        let trimmed = text.trimmingCharacters(in: .whitespaces).lowercased().replacingOccurrences(of: ",", with: "")
            .replacingOccurrences(of: "tokens", with: "").trimmingCharacters(in: .whitespaces)
        let scale: Double = trimmed.hasSuffix("m") ? 1_000_000 : trimmed.hasSuffix("k") ? 1_000 : 1
        let number = scale == 1 ? trimmed : String(trimmed.dropLast())
        return Double(number).map { Int64(($0 * scale).rounded()) }.flatMap { $0 > 0 ? $0 : nil }
    }
}

/// A KPI tile of the detail: label, big value with its unit, and an optional mark under it.
private struct Tile<Footer: View>: View {
    let label: String
    let value: String
    let unit: String?
    @ViewBuilder let footer: () -> Footer
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s4) {
                Text(skin.labelCased(label)).citadelFont("t10", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.muted))
                HStack(alignment: .firstTextBaseline, spacing: skin.size.s4) {
                    Text(value).citadelFont("t24", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                    if let unit { Text(unit).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted)) }
                }
                footer()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

/// A quoted note: "**Toma (Lead):** CIT-62 is the risk…".
struct Quote: View {
    let who: String?
    let text: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        (Text(who.map { "\($0): " } ?? "").foregroundStyle(skin.color(skin.text.primary)).bold()
            + Text(text).foregroundStyle(skin.color(skin.text.muted)))
            .citadelFont("t12")
            .lineSpacing(skin.size.s3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                skin.color(skin.palette.white).opacity(skin.opacity.o05),
                in: RoundedRectangle(cornerRadius: skin.size.s8))
    }
}
