import CitadelClient
import Foundation

/// A sprint of a project, for the issue's sprint menu (planned and active ones take issues; an empty planned one
/// can be deleted).
struct ProjectSprintInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    /// `planned`, `active`, `closed`, or a newer server's word.
    var state: String
}

extension Schemas.PrState: OpenWord {}

/// An issue's pull request on one repo (API minor 16), as the server keeps it: it survives a reconnect, unlike
/// the `pr.*` events it replaces on the thread.
struct IssuePRInfo: Identifiable, Equatable, Sendable {
    var id: Int64 { repoID }
    let repoID: Int64
    var repo: String
    /// `requested`, `open`, `merging`, `merged`, `closed`, or a newer server's word.
    var state: String
    var title: String
    var number: Int64?
    var url: String?
    var head: String
    var base: String
    /// `none`, `pending`, `success`, `failure`, or a newer server's word.
    var checks: String
    /// What `checks` is made of when the token cannot read every check.
    var checksNote: String?
    /// The forge's last refusal ("push rejected: …").
    var lastError: String?
    /// Why the runner's push was refused for good; it opens once the branch is on the forge.
    var pushHeld: String?
    /// When opening found its head branch not pushed (it waits for a later run's push).
    var unpushedAt: Date?
}

extension IssuePRInfo {
    init(_ pr: Schemas.IssuePr) {
        self.init(
            repoID: pr.repoId, repo: pr.repo, state: pr.state.word, title: pr.title, number: pr.number, url: pr.url,
            head: pr.head, base: pr.base, checks: pr.checks, checksNote: pr.checksNote, lastError: pr.lastError,
            pushHeld: pr.pushHeld, unpushedAt: pr.unpushedAt)
    }
}

/// What a comment you posted did: the comment, and the agent it woke (API minor 14 targets it).
struct PostedComment: Equatable, Sendable {
    var comment: CommentInfo
    var wokeAgentID: Int64?
}

/// The issue-level writes of API minors 12–14, on the agent thread (screen 07): blockers, the `block` transition
/// naming its blocker, an issue joining or leaving a sprint (an active one too: a scope change), deleting an empty
/// planned sprint, and a comment that names the agent it wakes. Each write returns `nil` (or its value) when done,
/// else the server's answer for the 11 G error state.
extension CitadelServer {
    /// The issues that block it.
    func blockers(issue: Int64) async -> [IssueInfo]? {
        await read("listBlockers") {
            guard case .ok(let ok) = try await client.listBlockers(path: .init(id: issue)) else { return nil }
            return try ok.body.json.map(IssueInfo.init)
        }
    }

    /// Links `blocker` as blocking `issue`; the issue's state is unchanged (block it with `block`).
    func linkBlocker(issue: Int64, blocker: Int64) async -> ServerAnswer? {
        await act { try await client.linkBlocker(path: .init(id: issue, blockerId: blocker)) }
    }

    /// Unlinks it; the issue unblocks (and its next actor wakes) when that was its last open blocker.
    func unlinkBlocker(issue: Int64, blocker: Int64) async -> ServerAnswer? {
        await act { try await client.unlinkBlocker(path: .init(id: issue, blockerId: blocker)) }
    }

    /// Blocks the issue on `blocker` (linked in the same step), or on its open blockers when `nil`.
    func block(issue: Int64, on blocker: Int64?) async -> ServerAnswer? {
        await act {
            try await client.transitionIssue(
                path: .init(id: issue), body: .json(.block(.init(blockerIssueId: blocker, kind: .block))))
        }
    }

    /// Puts the issue in `sprint` (planned, or active: a scope change that needs points), or takes it out of its
    /// planned or active sprint when `nil`.
    func setSprint(issue: Int64, sprint: Int64?) async -> ServerAnswer? {
        await act { try await client.setIssueSprint(path: .init(id: issue), body: .json(.init(sprintId: sprint))) }
    }

    /// Deletes a planned sprint with no issues whose commit is not waiting on an approval.
    func deleteSprint(_ sprint: Int64) async -> ServerAnswer? {
        await act { try await client.deleteSprint(path: .init(id: sprint)) }
    }

    /// A project's sprints, newest first.
    func sprints(project: Int64) async -> [ProjectSprintInfo]? {
        await read("listSprints") {
            guard case .ok(let ok) = try await client.listSprints(path: .init(id: project)) else { return nil }
            return try ok.body.json.map { ProjectSprintInfo(id: $0.id, name: $0.name, state: $0.state.word) }
                .sorted { $0.id > $1.id }
        }
    }

    /// The issue's pull requests, one per repo it asked for, in its project's repo order.
    func pullRequests(issue: Int64) async -> [IssuePRInfo]? {
        await read("listIssuePrs") {
            guard case .ok(let ok) = try await client.listIssuePrs(path: .init(id: issue)) else { return nil }
            return try ok.body.json.map(IssuePRInfo.init)
        }
    }

    /// A project's issues, for picking a blocker.
    func projectIssues(_ project: Int64) async -> [IssueInfo]? {
        await read("listProjectIssues") {
            guard case .ok(let ok) = try await client.listProjectIssues(path: .init(id: project)) else { return nil }
            return try ok.body.json.map(IssueInfo.init)
        }
    }

    /// Posts your comment: it answers the issue's newest open question and wakes `wake` — or, when `nil`, the agent
    /// it @mentions, else the issue's working agent. Answers whom it woke.
    func post(
        issue: Int64, body: String, wake: Int64?, idempotencyKey: String = UUID().uuidString
    ) async -> Result<PostedComment, ServerAnswer> {
        await attempt({
            try await client.postComment(
                path: .init(id: issue),
                body: .json(.init(body: body, idempotencyKey: idempotencyKey, wakeAgentId: wake)))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            let posted = try ok.body.json
            return PostedComment(comment: CommentInfo(posted.comment), wokeAgentID: posted.wokeAgentId)
        }
    }
}
