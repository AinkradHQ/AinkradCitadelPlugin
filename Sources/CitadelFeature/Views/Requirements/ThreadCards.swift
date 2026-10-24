import AinkradAppKit
import SwiftUI

/// An approval inside a requirement thread — the same server approval as screen 06: the plan (decision #40,
/// decided here when it waits on you), a QA verdict with its PRs (one merge for all of them, decision #51), or
/// anything else as a line that opens the inbox.
struct ThreadApprovalCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let approval: ApprovalInfo
    let at: Date
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    private var isPending: Bool { approval.status == "pending" }
    private var f: [String: String] { approval.fields }

    var body: some View {
        switch approval.kind {
        case "plan_approval": plan
        case "pr_merge": merge
        default: other
        }
    }

    private var plan: some View {
        let tasks = approval.lists["tasks"] ?? []
        let epics = Set(tasks.compactMap { $0["epic"] ?? $0["epic_id"] }).count
        let title = [
            "Plan", epics > 0 ? Wording.count(epics, "epic") : nil, Wording.count(tasks.count, "task"),
            f["points"].map { "\($0) pts" },
        ]
        .compactMap { $0 }.joined(separator: " · ")
        return AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                HStack(spacing: skin.size.s8) {
                    verdict(pending: "plan to approve", done: "✓ approved")
                    Text(title).citadelFont("t13", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                }
                Text(planMeta).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                if isPending {
                    HStack(spacing: skin.size.s8) {
                        AinkradButton(title: "Approve plan") { store.decide(approval, approve: true) }
                            .compact().fixedSize()
                        AinkradButton(title: "Send back", style: .secondary) { store.decide(approval, approve: false) }
                            .compact().fixedSize()
                        AinkradButton(title: "Open in Approvals", style: .ghost) { openInbox() }
                            .borderless().secondaryAccent().compact().fixedSize()
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .rim(isPending ? .warning : nil)
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

    private var merge: some View {
        let prs = approval.lists["prs"] ?? []
        let key = model.issue(approval.issueID)?.key ?? f["key"] ?? "The issue"
        return AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                HStack(spacing: skin.size.s8) {
                    verdict(pending: "✓ QA passed", done: approval.status == "approved" ? "✓ merged" : approval.status)
                    Text("\(key) · \(prs.count == 1 ? "1 PR" : "\(prs.count) PRs")").citadelFont(
                        "t13", weight: "semibold"
                    )
                    .foregroundStyle(skin.color(skin.text.primary))
                    Spacer(minLength: skin.size.s8)
                    if isPending {
                        AinkradButton(title: "Review merge…") { openInbox() }.compact().fixedSize()
                    }
                }
                ForEach(Array(prs.enumerated()), id: \.offset) { _, pr in
                    HStack(spacing: skin.size.s8) {
                        AinkradChip(label: pr["repo"] ?? "repo", systemName: "arrow.triangle.branch")
                        Text("#\(pr["pr"] ?? "?")").citadelFont("t11", mono: true)
                            .foregroundStyle(skin.color(skin.text.faint))
                        Spacer(minLength: 0)
                    }
                }
                if prs.count > 1 {
                    Text("One merge approval for all · \(key) is done when every one is merged").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .rim(.success)
    }

    private var other: some View {
        let summary = model.summary(approval)
        return AinkradCard(onTap: openInbox) {
            HStack(spacing: skin.size.s8) {
                TypeGlyph(glyph: summary.glyph, tone: summary.tone)
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text(summary.title).citadelFont("t12", weight: "medium").lineLimit(1)
                    Text(summary.subtitle).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
        }
    }

    @ViewBuilder private func verdict(pending: String, done: String) -> some View {
        if isPending {
            AinkradBadge(text: pending, status: approval.kind == "pr_merge" ? .success : .warning)
        } else {
            AinkradBadge(text: done, status: approval.status == "approved" ? .success : .neutral)
        }
    }

    private func openInbox() {
        store.selectedApproval = approval.id
        store.screen = .approvals
    }
}

/// Artifacts an agent published, two to a row: an icon or the image, the name, the type and size. Opens screen 13.
struct ArtifactPair: View {
    let store: CitadelStore
    let model: CompanyModel
    let artifacts: [ArtifactInfo]
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: skin.size.s6), GridItem(.flexible(), spacing: skin.size.s6)],
            alignment: .leading, spacing: skin.size.s6
        ) {
            ForEach(artifacts) { artifact in
                ArtifactLink(model: model, artifact: artifact) {
                    model.artifactsPage.selectedID = artifact.id
                    store.screen = .artifacts
                }
                .onAppear { store.loadPreview(artifact) }
            }
        }
    }
}

private struct ArtifactLink: View {
    let model: CompanyModel
    let artifact: ArtifactInfo
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        AinkradCard(onTap: open) {
            HStack(spacing: skin.size.s10) {
                if let image = model.artifactsPage.images[artifact.id] {
                    Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                        .frame(width: skin.size.s64, height: skin.size.s40)
                        .clipShape(RoundedRectangle(cornerRadius: skin.size.s4))
                } else {
                    Image(systemName: artifact.isImage ? "photo" : "doc.text").foregroundStyle(theme.accentSecondary)
                }
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text(artifact.name).citadelFont("t12").lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(skin.color(skin.text.primary))
                    Text(artifact.isImage ? artifact.kind : "\(artifact.kind) · \(ScopedSetting.bytes(artifact.size))")
                        .citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                }
                Spacer(minLength: 0)
            }
        }
        .brightness(hovering ? skin.opacity.o05 : 0)
        .onHover { hovering = $0 }
        .help(artifact.name)
    }
}
