import AinkradAppKit
import SwiftUI

/// An approval inside a requirement thread (`.tl-card`) — the same server approval as screen 06: the plan
/// (decision #40, decided here when it waits on you) with its epics, a QA verdict with its PRs (one merge for all
/// of them, decision #51), or anything else as a line that opens the inbox.
struct ThreadApprovalCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let requirement: RequirementInfo
    let approval: ApprovalInfo
    let at: Date
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    private var isPending: Bool { approval.status == "pending" }
    private var f: [String: String] { approval.fields }
    private var plan: PlanTree? { model.requirementsPage.plans[requirement.id] }

    var body: some View {
        switch approval.kind {
        case "plan_approval": planCard
        case "pr_merge": mergeCard
        default: other
        }
    }

    private var planCard: some View {
        let tasks = approval.lists["tasks"] ?? []
        let epicCount = plan?.epics.count ?? Set(tasks.compactMap { $0["epic"] ?? $0["epic_id"] }).count
        let taskCount = plan?.tasks ?? tasks.count
        let title = [
            "Plan", epicCount > 0 ? Wording.count(epicCount, "epic") : nil, Wording.count(taskCount, "task"),
            f["points"].map { "\($0) pts" },
        ]
        .compactMap { $0 }.joined(separator: " · ")
        let tone = isPending ? status.warning : status.success
        return TimelineCard(tone: tone) {
            CardHead(
                systemImage: "text.alignleft", tone: tone, title: title, subtitle: planMeta,
                badge: isPending ? "waiting for you" : approval.status == "approved" ? "✓ approved" : approval.status)
            if let plan, !plan.epics.isEmpty {
                VStack(alignment: .leading, spacing: skin.size.s6) {
                    ForEach(plan.epics) { epic in epicRow(epic, tone: tone) }
                }
            }
            HStack(spacing: skin.size.s8) {
                if plan != nil {
                    AinkradButton(
                        title: "View plan · \(Wording.count(epicCount, "epic")) · \(Wording.count(taskCount, "task"))",
                        style: .ghost
                    ) {
                        model.requirementsPage.drawer = [.plan]
                    }
                    .borderless().secondaryAccent().compact().fixedSize()
                }
                Spacer(minLength: 0)
                if isPending {
                    AinkradButton(title: "Ask for changes…", style: .secondary) {
                        model.requirementsPage.askingChanges = true
                    }
                    .compact().fixedSize()
                    AinkradButton(title: "Approve plan") { store.approvePlan(approval, requirement: requirement) }
                        .compact().fixedSize()
                }
            }
        }
    }

    private func epicRow(_ epic: PlanEpic, tone: Color) -> some View {
        let done = epic.tasks.filter { $0.state == "done" }.count
        return HStack(spacing: skin.size.s10) {
            Text(epic.title).citadelFont("t12", weight: "medium").lineLimit(1)
                .foregroundStyle(skin.color(skin.text.primary))
                .frame(width: skin.size.s160, alignment: .leading)
            ProgressLine(value: epic.tasks.isEmpty ? 0 : Double(done) / Double(epic.tasks.count), tint: tone)
            Text(verbatim: "\(done)/\(epic.tasks.count)").citadelFont("t11", mono: true)
                .foregroundStyle(skin.color(skin.text.faint)).frame(width: skin.size.s34, alignment: .trailing)
        }
    }

    /// "you approved Mon 10:04", "waiting on you since 09:31".
    private var planMeta: String {
        let when = RequirementThreadView.time(at)
        switch approval.status {
        case "approved": return "you approved \(when)"
        case "pending": return "waiting on you since \(when) · nothing starts before you approve"
        default: return "\(approval.status) \(when)"
        }
    }

    private var mergeCard: some View {
        let prs = approval.lists["prs"] ?? []
        let key = model.issue(approval.issueID)?.key ?? f["key"] ?? "the issue"
        let merged = approval.status == "approved"
        return TimelineCard(tone: status.success) {
            HStack(spacing: skin.size.s12) {
                CardHead(
                    systemImage: "checkmark.shield", tone: status.success, title: "QA passed · \(key)",
                    subtitle:
                        "\(Wording.count(prs.count, "pull request")) · \(merged ? "merged" : prs.count > 1 ? "one approval merges both" : "waiting for the merge")",
                    badge: merged ? "merged" : nil)
                if isPending {
                    AinkradButton(title: "Review merge…") { openInbox() }.compact().fixedSize()
                }
            }
            ForEach(Array(prs.enumerated()), id: \.offset) { _, pr in prRow(pr) }
        }
    }

    private func prRow(_ pr: [String: String]) -> some View {
        let repo = pr["repo"] ?? "repo"
        let info = model.issuePRs[approval.issueID ?? 0]?.first { $0.repo == repo }
        let diff = approval.issueID.flatMap { model.diff(issue: $0, repo: repo) }
        return HStack(spacing: skin.size.s10) {
            Text(repo).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
            Text("#\(pr["pr"] ?? info?.number.map(String.init) ?? "?")").citadelFont("t11", mono: true)
                .foregroundStyle(skin.color(skin.text.faint))
            if let checks = info?.checks, checks != "none" {
                Text(checks == "success" ? "✓ checks" : "checks \(checks)").citadelFont("t10_5")
                    .foregroundStyle(checks == "success" ? status.success : status.warning)
                    .padding(.horizontal, skin.size.s7).padding(.vertical, skin.size.s1)
                    .background(
                        (checks == "success" ? status.success : status.warning).opacity(skin.opacity.o12),
                        in: RoundedRectangle(cornerRadius: skin.size.s5))
            }
            Spacer(minLength: skin.size.s8)
            if let diff {
                (Text(verbatim: "+\(diff.insertions)").foregroundStyle(status.success) + Text(" ")
                    + Text(verbatim: "−\(diff.deletions)").foregroundStyle(status.danger))
                    .citadelFont("t11", mono: true)
                DiffBar(insertions: diff.insertions, deletions: diff.deletions)
            }
        }
        .padding(.vertical, skin.size.s6)
    }

    private var other: some View {
        let summary = model.summary(approval)
        return ReceiptRow(glyph: summary.glyph, tint: summary.tone.tint(skin), action: openInbox) {
            Text(summary.title).foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
            Text(summary.subtitle).foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
        }
    }

    private func openInbox() {
        store.selectedApproval = approval.id
        store.screen = .approvals
    }
}

extension CompanyModel {
    /// A repo's latest worktree diff on an issue, from its runs.
    func diff(issue: Int64, repo: String) -> RepoDiffInfo? {
        runs.values.filter { $0.issueID == issue && !$0.diffRepos.isEmpty }.max { $0.queuedAt < $1.queuedAt }?
            .diffRepos.first { $0.repo == repo }
    }
}

/// `.tl-card`: r16, a tone-tinted gradient and rim.
struct TimelineCard<Content: View>: View {
    let tone: Color
    @ViewBuilder var content: () -> Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        VStack(alignment: .leading, spacing: skin.size.s10) { content() }
            .padding(skin.size.s14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [tone.opacity(skin.opacity.o08), skin.color(.palette("foreground", skin.opacity.o03))],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(shape.strokeBorder(tone.opacity(skin.opacity.o35), lineWidth: 1))
    }
}

/// `.tl-ch`: a 32 pt tinted icon tile, the title and sub, and an optional badge on the right.
struct CardHead: View {
    let systemImage: String
    let tone: Color
    let title: String
    let subtitle: String
    var badge: String?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s12) {
            Image(systemName: systemImage).citadelFont("t14").foregroundStyle(tone)
                .frame(width: skin.size.s32, height: skin.size.s32)
                .background(tone.opacity(skin.opacity.o25), in: RoundedRectangle(cornerRadius: skin.size.s10))
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(title).citadelFont("t13", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                Text(subtitle).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
            }
            Spacer(minLength: skin.size.s8)
            if let badge {
                Text(badge).citadelFont("t10_5", weight: "semibold").foregroundStyle(tone)
                    .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
                    .background(tone.opacity(skin.opacity.o14), in: RoundedRectangle(cornerRadius: skin.size.s6))
                    .fixedSize()
            }
        }
    }
}

/// A thin progress track (`.bar`): 6 pt, rounded.
struct ProgressLine: View {
    let value: Double
    let tint: Color
    var height: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(skin.color(.palette("foreground", skin.opacity.o08)))
                Capsule().fill(tint).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: height ?? skin.size.s6)
    }
}

/// `.tl-diff`: a 70 pt green/red split of a diff's lines.
struct DiffBar: View {
    let insertions: Int64
    let deletions: Int64
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let total = Double(max(insertions + deletions, 1))
        GeometryReader { geo in
            HStack(spacing: skin.size.s1) {
                status.success.frame(width: geo.size.width * Double(insertions) / total)
                status.danger
            }
        }
        .frame(width: skin.size.s70, height: skin.size.s6)
        .clipShape(Capsule())
    }
}

/// "✓ 15 permissions decided inside runs · show ›" — every decided permission folded into one receipt; tap shows
/// the tool counts.
struct PermissionsReceipt: View {
    let approvals: [ApprovalInfo]
    @State private var open = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            ReceiptRow(glyph: "✓", trailing: open ? "hide ‹" : "show ›", action: { open.toggle() }) {
                Text("\(Wording.count(approvals.count, "permission")) decided inside runs")
            }
            if open {
                Text(HubLine.toolCounts(approvals)).citadelFont("t11", mono: true)
                    .foregroundStyle(skin.color(skin.text.faint)).padding(.leading, skin.size.s34)
            }
        }
    }
}
