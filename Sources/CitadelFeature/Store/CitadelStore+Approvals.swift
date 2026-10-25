import AinkradAppKit
import SwiftUI

/// Where an approved permission escalation applies (the stage's "Allow for" picker).
enum AllowScope: String, CaseIterable, Hashable {
    case once, issue, project
}

/// The approvals stage (06): the reads one approval needs, and its decisions with the prototype's toasts. A refusal
/// is the 11 G banner, as everywhere.
extension CitadelStore {
    /// What the selected approval's body draws beyond its payload: a sprint's velocity series, a merge's PRs and
    /// diff, a permission's run (for its runner) and its project's policy.
    func loadApprovalContext(_ approval: ApprovalInfo) {
        guard let server, let model else { return }
        Task {
            switch approval.kind {
            case "sprint_commit":
                guard let project = model.sprintProject(approval), model.velocitySeries[project.id] == nil else {
                    return
                }
                if let (average, completed) = await server.velocityPoints(project: project.id) {
                    model.velocity[project.id] = average
                    model.velocitySeries[project.id] = completed
                }
            case "pr_merge":
                guard let issue = approval.issueID else { return }
                if let prs = await server.pullRequests(issue: issue) { model.issuePRs[issue] = prs }
                if let diff = await server.issueDiff(issue) { model.issueDiffs[issue] = diff }
            case "permission_escalation":
                if let id = approval.fields["run"].flatMap(Int64.init), model.runs[id] == nil,
                    let run = await server.run(id)
                {
                    model.runs[id] = run
                }
                if let project = model.issue(approval.issueID)?.projectID,
                    model.projectsPage.policies[project] == nil, let policy = await server.policy(project: project)
                {
                    model.projectsPage.policies[project] = policy
                }
            default: break
            }
        }
    }

    /// Approve or reject from the stage, the reply going with it (and as the reason of a rejection); then the
    /// prototype's toast. A budget raise carries the new cap less the current one.
    func decideOnStage(
        _ approval: ApprovalInfo, approve: Bool, raiseTokens: Int64? = nil, reply: String, scope: AllowScope = .once
    ) {
        guard let server, let model else { return }
        let reply = reply.trimmingCharacters(in: .whitespacesAndNewlines)
        let text = reply.isEmpty ? nil : reply
        let asker = model.replyTarget(approval)
        let failure = model.summary(approval).title
        Task {
            var answer: ServerAnswer?
            switch (approve, scope) {
            case (true, .issue): answer = await server.allowForIssue(approval: approval.id, reply: text)
            case (true, .project):
                answer = await saveProjectRule(approval, server: server, model: model)
                if answer == nil {
                    answer = await server.decision(approval: approval.id, approve: true, raiseTokens: nil, reply: text)
                }
            default:
                answer = await server.decision(
                    approval: approval.id, approve: approve, raiseTokens: raiseTokens, reply: text)
            }
            if let answer {
                actionFailure = ActionFailure(
                    title: "Couldn't \(approve ? "approve" : "reject") “\(failure)”", answer: answer,
                    outcome: approve ? "Nothing was approved." : "Nothing was rejected.")
                return
            }
            model.answer(approval, approved: approve, reply: text)
            if approve {
                toast(AinkradRichToast(title: "Approved", body: model.approvedLine(approval), status: .success))
                if scope != .once {
                    let key = model.issue(approval.issueID)?.key ?? "the issue"
                    toast(
                        AinkradRichToast(
                            title: "Rule saved for \(scope == .issue ? key : "this project")",
                            body: "Same command won't ask again."))
                }
                if let text { toast(AinkradRichToast(title: "Reply sent with your decision", body: "“\(text)”")) }
            } else {
                toast(
                    AinkradRichToast(
                        title: "Rejected", body: text.map { "“\($0)” sent to \(asker)" } ?? "\(asker) was told"))
            }
        }
    }

    /// "Reply only": the reply as a comment on the approval's issue, waking the asker; the decision still waits.
    func replyOnStage(_ approval: ApprovalInfo, text: String, sent: @escaping @MainActor () -> Void) {
        let body = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !body.isEmpty, let issue = approval.issueID, let server, let model else { return }
        let agent = model.replyAgent(approval)
        Task {
            switch await server.post(issue: issue, body: body, wake: agent) {
            case .success(let posted):
                model.posted(posted.comment)
                sent()
                toast(
                    AinkradRichToast(
                        title: "Reply sent to \(model.replyTarget(approval))",
                        body: "Woken with your message · still waiting on your decision",
                        icon: model.agent(agent).map { AnyView(AgentFigure(agent: $0, model: model, size: 28)) }))
            case .failure(let answer):
                actionFailure = ActionFailure(
                    title: "Couldn't send your reply to \(model.replyTarget(approval))", answer: answer,
                    outcome: "Nothing was sent; nobody was woken.")
            }
        }
    }

    /// "This project": the escalated call added to the project policy's allowlist (`<tool>:<command prefix>`).
    private func saveProjectRule(_ approval: ApprovalInfo, server: CitadelServer, model: CompanyModel) async
        -> ServerAnswer?
    {
        guard let project = model.issue(approval.issueID)?.projectID else {
            return ServerAnswer(status: 400, code: "no_project", message: "this escalation has no project")
        }
        guard var policy = await server.policy(project: project) else {
            return ServerAnswer(status: 404, code: "not_found", message: "the project's policy could not be read")
        }
        let rule = PermissionAsk(approval.fields).rule
        if !policy.allow.contains(rule) { policy.allow.append(rule) }
        switch await server.setPolicy(project: project, policy) {
        case .success(let saved):
            model.projectsPage.policies[project] = saved
            return nil
        case .failure(let answer): return answer
        }
    }
}

/// What a permission escalation asks for, from its payload: the tool and the command's first two words — which is
/// also the allowlist rule "This project" saves (`Bash:cargo add`).
struct PermissionAsk {
    let tool: String
    let command: String

    init(_ fields: [String: String]) {
        tool = fields["tool"] ?? "a tool"
        command = ToolLine.argument(fields)
    }

    /// `cargo add`, or the tool alone for a call without a command.
    var prefix: String { command.split(separator: " ").prefix(2).joined(separator: " ") }
    var rule: String { prefix.isEmpty ? tool : "\(tool):\(prefix)" }
}

extension CompanyModel {
    /// The project a sprint commit plans, from its issues' key prefix.
    func sprintProject(_ approval: ApprovalInfo) -> ProjectInfo? {
        let key = (approval.lists["issues"] ?? approval.lists["tasks"] ?? []).first?["key"]
        return key.flatMap { key in projects.first { key.hasPrefix("\($0.key)-") } }
    }

    /// The approved toast's line, per kind.
    func approvedLine(_ approval: ApprovalInfo) -> String {
        let f = approval.fields
        let key = issue(approval.issueID)?.key
        switch approval.kind {
        case "permission_escalation": return "\(replyTarget(approval))'s run resumed"
        case "budget_overrun": return "\(key ?? "The") cap raised — \(replyTarget(approval)) continues"
        case "pr_merge":
            let prs = (approval.lists["prs"] ?? []).map { "\($0["repo"] ?? "repo") #\($0["pr"] ?? "?")" }
            return "Merging \(prs.joined(separator: ", then "))\(key.map { " · \($0) done when merged" } ?? "")"
        case "sprint_commit":
            let count = (approval.lists["issues"] ?? []).count
            return
                "\(summary(approval).title.replacingOccurrences(of: "Commit s", with: "S")) committed · \(count) issues"
        case "hire_agent": return "\(f["name"] ?? "The agent") hired"
        default: return summary(approval).title
        }
    }
}
