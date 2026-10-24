import AinkradAppKit
import SwiftUI

/// The issue's pull requests on the agent thread (API minor 16), read from the server so they survive a reconnect:
/// each repo's PR — its state, number, head → base and checks — and a refused push, a held push or a failed forge
/// call. A held push links to the `workflow_push` approval waiting on it.
struct IssuePRList: View {
    let store: CitadelStore
    let model: CompanyModel
    let issue: Int64
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let prs = model.issuePRs[issue] ?? []
        if !prs.isEmpty {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                ForEach(prs) { pr in row(pr) }
            }
            .padding(.horizontal, skin.size.s20)
            .padding(.bottom, skin.size.s8)
        }
    }

    private func row(_ pr: IssuePRInfo) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s4) {
            HStack(spacing: skin.size.s10) {
                AinkradBadge(text: pr.repo, tint: theme.accentSecondary)
                Text(Self.line(pr)).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    .lineLimit(1).truncationMode(.middle)
                Spacer(minLength: skin.size.s8)
                AinkradBadge(text: pr.state, status: Self.status(pr.state))
                if let url = pr.url.flatMap(URL.init(string:)) {
                    AinkradButton(title: "Open PR", style: .ghost) { NSWorkspace.shared.open(url) }
                        .borderless().secondaryAccent().compact().fixedSize()
                }
            }
            if let note = pr.checksNote, !note.isEmpty {
                Text("Checks: \(note)").citadelFont("t11").foregroundStyle(status.warning)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let held = pr.pushHeld {
                if model.approvals.contains(where: { $0.kind == "workflow_push" && $0.issueID == issue }) {
                    AinkradBanner(
                        message: "Push held: \(held) A workflow push approval waits for you to push it by hand.",
                        status: .danger, actionTitle: "Open approvals →", action: { store.screen = .approvals })
                } else {
                    AinkradBanner(message: "Push held: \(held)", status: .danger)
                }
            }
            if let error = pr.lastError { AinkradBanner(message: error, status: .danger) }
            if let unpushed = pr.unpushedAt, pr.state == "requested" {
                Text("Waiting for \(pr.head) to be pushed (since \(Fmt.age(Date().timeIntervalSince(unpushed))) ago)")
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
            }
        }
        .padding(skin.size.s10)
        .background(
            skin.color(skin.palette.white).opacity(skin.opacity.o03), in: RoundedRectangle(cornerRadius: skin.size.s8))
    }

    /// "#42 · cit-64-spec → development · checks success" — no number while it is only requested.
    static func line(_ pr: IssuePRInfo) -> String {
        [pr.number.map { "#\($0)" }, "\(pr.head) → \(pr.base)", "checks \(pr.checks)"].compactMap { $0 }
            .joined(separator: " · ")
    }

    static func status(_ state: String) -> AinkradStatus {
        switch state {
        case "merged": .success
        case "open", "merging": .warning
        case "closed": .danger
        default: .neutral
        }
    }
}
