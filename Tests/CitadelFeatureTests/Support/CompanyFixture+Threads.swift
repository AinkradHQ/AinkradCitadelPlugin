import Foundation

@testable import CitadelFeature

/// Screen 07 as the prototype's `chat.js` shows it: Quill on MKT-8 asking you (with its draft attached), Kestrel on
/// CIT-42 unread, Rook's run lost on CIT-49, Pike on AMC-12.
@MainActor
extension CompanyFixture {
    static func threadsParity(_ model: CompanyModel) {
        threadsPage(model)
        model.issues[8]?.points = 3
        model.comments[42] = [
            CommentInfo(
                id: 11, issueID: 42, agentID: 4,
                body:
                    "The stream drops events after a reconnect because `replay_from` reads `>` instead of `>=` the client's last-seen id. Fixing the bound, then the 10-minute disconnect soak test from the acceptance criteria.",
                runID: 418),
            CommentInfo(
                id: 12, issueID: 42, agentID: nil,
                body: "Good. Make the plugin send Last-Event-ID on reconnect too, both repos in one PR pair.",
                runID: nil),
            CommentInfo(
                id: 13, issueID: 42, agentID: 4,
                body:
                    "Fixed the bound in `stream.rs` and the client sends the id now. Soak test next — I've asked for network to add `tokio-tungstenite`; it's in your approvals.",
                runID: nil),
        ]
        model.comments[49] = [
            CommentInfo(
                id: 31, issueID: 49, agentID: 8,
                body: "Starting on the retry budget: `runner_lost` retries once, then escalates to the Lead.",
                runID: nil)
        ]
        model.comments[12] = [
            CommentInfo(
                id: 21, issueID: 12, agentID: nil,
                body:
                    "Scaffold the Citadel plugin from the template — copy a fresh plugin's scaffold commit, don't use `ainkrad new`.",
                runID: nil),
            CommentInfo(
                id: 22, issueID: 12, agentID: 11,
                body:
                    "Understood — the installed CLI embeds a stale template. Copying Forge's scaffold commit and renaming.",
                runID: 421),
        ]
        model.artifactsPage.items = [
            ArtifactInfo(
                id: 301, name: "launch-post-draft.md", kind: "draft", mime: "text/markdown", size: 6_100,
                preview: "text", sha256: "", agentID: 15, issueID: 8, requirementID: 10, runID: 405,
                createdAt: now.addingTimeInterval(-0.2 * 86_400), redactions: 0)
        ]
        let page = model.threadsPage
        // Rook's CIT-64 run belongs to the runs / why-stuck screens; the threads list shows one thread per agent.
        model.runs[430] = nil
        // Kestrel's newest work is unread; Pike's was looked at.
        page.baseline = now.addingTimeInterval(-10 * 60)
        page.seen[ThreadKey(agentID: 11, issueID: 12)] = now
    }
}
