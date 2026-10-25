import AinkradAppKit
import SwiftUI

/// The decision stage: the hero, the body for the approval's kind (rising in), and the docked reply with the
/// decision buttons. The reply goes with the decision — and is the reason when you reject. ⌘↵ approves, ⌘⌫
/// rejects (both work while typing).
struct ApprovalDetail: View {
    let store: CitadelStore
    let model: CompanyModel
    let approval: ApprovalInfo
    /// Bumped by R on the list: the reply takes the focus.
    var replyFocus = 0
    @State private var reply = ""
    @State private var newCap: Double = 0
    @State private var scope: AllowScope = .once
    @Environment(\.ainkradSkin) private var skin

    private var isPending: Bool { approval.status == "pending" }
    private var f: [String: String] { approval.fields }
    private var kind: ApprovalFilter { ApprovalFilter.of(approval) }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            hero
                .padding(.horizontal, skin.size.s14)
                .padding(.top, skin.size.s14)
                .padding(.bottom, skin.size.s6)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s12) {
                    if !isPending { decided.riseIn() }
                    ApprovalBody(
                        store: store, model: model, approval: approval, newCap: $newCap, scope: $scope,
                        isPending: isPending)
                }
                .padding(.horizontal, skin.size.s14)
                .padding(.top, skin.size.s8)
                .padding(.bottom, skin.size.s14)
                .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            if isPending { dock }
        }
        .onAppear {
            store.loadApprovalContext(approval)
            if let cap = BudgetNumbers(f)?.cap { newCap = Double(cap) * 1.2 }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        let state =
            isPending
            ? HeroState(
                text: ["waiting on you", approval.askedAgo()].compactMap { $0 }.joined(separator: " · "),
                tint: kind.tint(skin))
            : HeroState(
                text: ["\(approval.status) by you", approval.decidedAgo()].compactMap { $0 }.joined(separator: " · "),
                tint: approval.status == "approved"
                    ? skin.color(skin.palette.success) : skin.color(skin.palette.warning))
        return ApprovalHero(
            tint: kind.tint(skin), systemImage: kind.systemImage, crumb: ApprovalCard.label(approval),
            title: heroTitle, state: state, chips: chips, agents: model.involved(approval), model: model)
    }

    private var heroTitle: String {
        let key = model.issue(approval.issueID)
        switch approval.kind {
        case "sprint_commit":
            let base = model.summary(approval).title
            guard let start = f["starts_on"], let end = f["ends_on"] else { return base }
            return "\(base) · \(Self.day(start)) → \(Self.day(end))"
        case "pr_merge":
            guard let key else { return model.summary(approval).title }
            return "Merge \(key.key) · \(key.title)"
        case "budget_overrun":
            guard let numbers = BudgetNumbers(f), numbers.cap > 0 else { return model.summary(approval).title }
            let percent = Int((Double(numbers.spent) / Double(numbers.cap) * 100).rounded())
            let what = key?.key ?? "\(f["scope"] ?? "its") budget"
            return "\(model.replyTarget(approval)) is at \(percent)% of the \(what) cap"
        case "hire_agent":
            return "Hire \(f["name"] ?? "an agent"), a \(f["role"] ?? "new") agent"
        default: return model.summary(approval).title
        }
    }

    private var chips: [HeroChip] {
        let asker = model.agent(approval.requestedBy)
        let issue = model.issue(approval.issueID)
        switch approval.kind {
        case "sprint_commit":
            return [
                HeroChip(agent: asker, text: asker?.nameAndRole ?? "", model: model),
                HeroChip(text: "policy: you approve", model: model),
            ]
        case "pr_merge":
            let head = issue.flatMap { model.issuePRs[$0.id]?.first?.head }
            return [
                issue.map { HeroChip(key: $0.key, model: model) },
                asker.map { HeroChip(text: "\($0.name) verified", model: model) },
                head.map { HeroChip(text: $0, mono: true, model: model) },
            ].compactMap { $0 }
        case "budget_overrun":
            let agent = model.agent(approval.agentID ?? approval.requestedBy)
            return [
                agent.map { HeroChip(agent: $0, text: $0.name, model: model) },
                issue.map { HeroChip(key: $0.key, text: $0.title, model: model) },
                HeroChip(text: "\(f["scope"] ?? "budget") · \(f["period"] ?? "period")", model: model),
            ].compactMap { $0 }
        case "hire_agent":
            return [
                asker.map { HeroChip(agent: $0, text: "proposed by \($0.nameAndRole)", model: model) },
                model.teamPath(of: approval.agentID).map { HeroChip(text: $0, model: model) },
            ].compactMap { $0 }
        case "permission_escalation":
            return [
                asker.map { HeroChip(agent: $0, text: $0.name, model: model) },
                issue.map { HeroChip(key: $0.key, model: model) },
                f["run"].map { HeroChip(text: "run #\($0) is waiting", model: model) },
            ].compactMap { $0 }
        default:
            return [asker.map { HeroChip(agent: $0, text: $0.nameAndRole, model: model) }].compactMap { $0 }
        }
    }

    // MARK: - Answered

    private var decided: some View {
        let approved = approval.status == "approved"
        let tint = approved ? skin.color(skin.palette.success) : skin.color(skin.palette.warning)
        return HStack(spacing: skin.size.s12) {
            Text(approved ? "✓" : "✕").citadelFont("t15", weight: "bold").foregroundStyle(tint)
                .frame(width: skin.size.s36, height: skin.size.s36)
                .background(tint.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s10))
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text("\(approved ? "Approved" : "Rejected") by you").citadelFont("t13", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.primary))
                Text(approval.reply.map { "You: \($0)" } ?? "\(model.replyTarget(approval)) was told and woken.")
                    .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s16)
        .padding(.vertical, skin.size.s14)
        .background(tint.opacity(skin.opacity.o08), in: RoundedRectangle(cornerRadius: skin.size.s16))
        .overlay(RoundedRectangle(cornerRadius: skin.size.s16).strokeBorder(tint.opacity(skin.opacity.o25)))
    }

    // MARK: - Dock

    private var dock: some View {
        ApprovalDock(
            reply: $reply, replyFocus: replyFocus,
            placeholder:
                "Reply to \(model.replyTarget(approval)) — sent with your decision, and the reason if you reject",
            onApprove: approve, onReject: { store.decideOnStage(approval, approve: false, reply: reply) }
        ) {
            side
        } decision: {
            AinkradDockButton(rejectTitle, tone: .danger) {
                store.decideOnStage(approval, approve: false, reply: reply)
            }
            AinkradDockButton(approveTitle, tone: .primary, isEnabled: canApprove, action: approve)
        }
    }

    @ViewBuilder private var side: some View {
        switch approval.kind {
        case "pr_merge":
            let urls = (approval.lists["prs"] ?? []).compactMap { $0["url"].flatMap(URL.init(string:)) }
            if !urls.isEmpty {
                AinkradDockButton(urls.count > 1 ? "Open PRs" : "Open PR", systemImage: "arrow.up.forward.square") {
                    urls.forEach { NSWorkspace.shared.open($0) }
                }
            }
        case "permission_escalation":
            if let run = f["run"].flatMap(Int64.init) {
                AinkradDockButton("Open run", systemImage: "play") { store.open(.run(run)) }
            }
        default:
            AinkradDockButton("Reply only", isEnabled: approval.issueID != nil) {
                store.replyOnStage(approval, text: reply) { reply = "" }
            }
            .ainkradTooltip(
                approval.issueID == nil ? "This approval has no issue to reply on" : "Sends the reply alone")
        }
    }

    private var rejectTitle: String {
        switch approval.kind {
        case "pr_merge": "Request changes"
        case "budget_overrun": "Stop at cap"
        case "workflow_push": "Drop the change"
        case "permission_escalation": "Deny"
        default: "Reject"
        }
    }

    private var approveTitle: String {
        switch approval.kind {
        case "sprint_commit": return "Commit sprint"
        case "pr_merge": return (approval.lists["prs"]?.count ?? 1) > 1 ? "Merge both" : "Merge"
        case "budget_overrun": return "Raise to \(Fmt.tokens(Int64(newCap.rounded())))"
        case "hire_agent": return "Hire \(f["name"] ?? "")".trimmingCharacters(in: .whitespaces)
        case "workflow_push": return "I pushed it"
        case "permission_escalation":
            switch scope {
            case .once: return "Allow once"
            case .issue: return "Allow for \(model.issue(approval.issueID)?.key ?? "the issue")"
            case .project: return "Allow for project"
            }
        default: return "Approve"
        }
    }

    /// A raise must lift the cap.
    private var canApprove: Bool { approval.kind != "budget_overrun" || raise != nil }

    /// The overrun's raise: the slider's new cap less the current one, in whole thousands of tokens.
    private var raise: Int64? {
        guard let cap = BudgetNumbers(f)?.cap else { return nil }
        let typed = Int64((newCap / 1000).rounded()) * 1000
        return typed > cap ? typed - cap : nil
    }

    private func approve() {
        guard isPending else { return }
        if approval.kind == "budget_overrun" {
            guard let raise else {
                store.toast(AinkradRichToast(title: "New cap must be above the current one", status: .danger))
                return
            }
            store.decideOnStage(approval, approve: true, raiseTokens: raise, reply: reply)
        } else {
            store.decideOnStage(approval, approve: true, reply: reply, scope: scope)
        }
    }

    /// "2026-10-27" → "Oct 27".
    static func day(_ text: String) -> String {
        guard let date = try? Date(text, strategy: Date.ISO8601FormatStyle().year().month().day()) else { return text }
        return date.formatted(.dateTime.month(.abbreviated).day())
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

/// A budget overrun's tokens: spent, and the cap with this period's raises.
struct BudgetNumbers {
    let spent: Int64
    let cap: Int64

    init?(_ f: [String: String]) {
        guard let spent = f["spent"].flatMap(Int64.init), let cap = f["token_cap"].flatMap(Int64.init) else {
            return nil
        }
        self.spent = spent
        self.cap = cap + (f["raised"].flatMap(Int64.init) ?? 0)
    }
}
