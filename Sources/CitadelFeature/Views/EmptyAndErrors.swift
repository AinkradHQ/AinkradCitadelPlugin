import AinkradAppKit
import SwiftUI

/// Mockup 11 A: a new server with no agents yet — what fills it, and the action that does.
struct NoAgentsView: View {
    let store: CitadelStore
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        VStack(spacing: 0) {
            PaneTitle(title: store.company?.name ?? CitadelApp.displayName, crumb: nil)
            // TODO(citadel#hire-template): both actions create hire approvals; they need the template and propose-agent
            // endpoints.
            AinkradEmptyState(
                icon: "building.columns", title: "Your company has no agents yet",
                message:
                    "Start from the Engineering template — a CTO and one scrum team (PO, Lead, two devs, QA, DevOps) with their skills — or propose agents one by one. Every new agent is a hire you approve.",
                actionTitle: "Use Engineering template", action: {}
            )
            .secondaryAction("Propose an agent…") {}
            .glyph("⛫").iconTint(theme.accentSecondary).secondaryAccent().compact()
            .disabled(true)
            .frame(maxWidth: skin.size.s520)
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// Mockup 11 G: the server refused an action — what it said, that nothing happened, and the one way forward.
struct ActionFailureView: View {
    let store: CitadelStore
    let failure: ActionFailure
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        AinkradEmptyState(
            icon: "xmark.circle", title: failure.title, message: failure.message,
            actionTitle: failure.answer.status == 409 ? "Review the new scope" : "Back to the approval",
            action: { store.actionFailure = nil }
        )
        .secondaryAction("Copy error") { failure.answer.copy() }
        .iconTint(status.danger).compact()
        .frame(maxWidth: skin.size.s440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

/// A refusal shown in place (a card, a sheet): what failed in red, and Copy error with the server's error id.
struct RefusalLine: View {
    let failure: ActionFailure
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: skin.size.s8) {
            Text("\(failure.title). \(failure.message)").citadelFont("t12").foregroundStyle(status.danger)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
            AinkradButton(title: "Copy error", style: .ghost) { failure.answer.copy() }
                .borderless().compact().fixedSize()
        }
        .transition(.opacity)
    }
}

/// Mockup 11 H: an ended run with no transcript — the summary stays.
struct NoTranscriptView: View {
    let store: CitadelStore
    let model: CompanyModel
    let run: RunInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let issue = model.issue(run.issueID)
        AinkradEmptyState(
            icon: "doc.plaintext", title: "This run's transcript is gone",
            message:
                "Nothing of it is on the server any more, or it never started. The summary stays: \(run.summaryLine(issue: issue?.key)).",
            actionTitle: issue.map { "Open \($0.key)" },
            action: issue.map { issue in
                {
                    store.selectedThread = ThreadKey(agentID: run.agentID, issueID: issue.id)
                    store.screen = .threads
                    store.detail = nil
                }
            }
        )
        .plainPrimary().compact()
        .frame(maxWidth: skin.size.s440)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

extension RunInfo {
    /// A run with nothing to replay: ended, and its transcript loaded empty.
    func hasNoTranscript(_ chunks: [TranscriptChunkInfo]?) -> Bool { !isLive && chunks?.isEmpty == true }

    /// "succeeded · 18m · $1.12 · CIT-12".
    func summaryLine(issue key: String?) -> String {
        var parts = [state]
        if let start = startedAt, let end = endedAt { parts.append(Fmt.age(end.timeIntervalSince(start))) }
        parts.append(costMicros.map { Fmt.dollars(micros: $0) } ?? "unpriced")
        if let key { parts.append(key) }
        return parts.joined(separator: " · ")
    }
}

extension CompanyModel {
    /// Mockup 11 E: "Last decision: merged CIT-61 (2 PRs) at 11:40." from the newest answered approval.
    func lastDecisionLine() -> String? {
        guard let last = answeredApprovals.first else { return nil }
        let approved = last.status == "approved"
        let key = issue(last.issueID)?.key ?? last.fields["key"]
        let what: String
        switch (last.kind, approved) {
        case ("pr_merge", true):
            let prs = last.lists["prs"]?.count ?? 0
            what = "merged \(key ?? "the PRs")\(prs > 1 ? " (\(prs) PRs)" : "")"
        default:
            let title = summary(last).title
            what = "\(approved ? "approved" : "denied") \(title.prefix(1).lowercased() + title.dropFirst())"
        }
        return "Last decision: \(what)."
    }
}
