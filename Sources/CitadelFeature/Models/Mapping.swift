import AinkradAppKit
import CitadelClient
import Foundation
import OpenAPIRuntime

typealias Schemas = Components.Schemas

/// An open enum on the wire (`anyOf: [enum, string]`): a known case, or a newer server's word.
protocol OpenWord {
    associatedtype Known: RawRepresentable where Known.RawValue == String
    var value1: Known? { get }
    var value2: String? { get }
}

extension OpenWord {
    var word: String { value1?.rawValue ?? value2 ?? "" }
}

extension Schemas.OrgRole: OpenWord {}
extension Schemas.AgentStatus: OpenWord {}
extension Schemas.Harness: OpenWord {}
extension Schemas.FigureState: OpenWord {}
extension Schemas.RunState: OpenWord {}
extension Schemas.ApprovalKind: OpenWord {}
extension Schemas.StuckKind: OpenWord {}
extension Schemas.RequirementState: OpenWord {}
extension Schemas.BudgetPeriod: OpenWord {}
extension Schemas.AccountStatus: OpenWord {}
extension Schemas.Billing: OpenWord {}
extension Schemas.TeamRole: OpenWord {}
extension Schemas.SprintState: OpenWord {}
extension Schemas.ProjectMode: OpenWord {}
extension Schemas.ApprovalStatus: OpenWord {}
extension Schemas.IssueState: OpenWord {}
extension Schemas.QuestionState: OpenWord {}
extension Schemas.RepairAction: OpenWord {}
extension Schemas.RunnerStatus: OpenWord {}

/// How an agent is drawn (decisions #61, #63): always the animated figure, never a letter.
enum AgentLook {
    /// The server's `figure_state`, with a hard error told apart from a stall: `confused` after a run that failed
    /// or lost its runner is `.error` (red dot); after a stall or a block it stays amber `confused`.
    static func figure(_ word: String, lastRunState: String? = nil) -> AinkradFigureState {
        let state = AinkradFigureState(rawValue: word) ?? .idle
        if state == .confused, let lastRunState, ["failed", "runner_lost", "timed_out"].contains(lastRunState) {
            return .error
        }
        return state
    }

    /// The palette stored at hire (`appearance.palette_id`); Muted while paused or retired; Neon Tide for an id
    /// this build doesn't know.
    static func palette(id: String, status: String) -> AinkradFigurePalette {
        if status == "paused" || status == "terminated" { return .muted }
        return AinkradFigurePalette.named(id) ?? .neonTide
    }

    /// The harness arc.
    static func harness(_ word: String) -> AinkradFigureHarness? {
        switch word {
        case "claude": .claude
        case "codex": .codex
        case "opencode": .openCode
        case "agy": .agy
        default: nil
        }
    }

    static func harnessName(_ word: String) -> String { harness(word)?.name ?? word }
}

extension AgentInfo {
    init(_ agent: Schemas.Agent) {
        self.init(
            id: agent.id, name: agent.name, role: agent.role, orgRole: agent.orgRole.word, harness: agent.harness.word,
            model: agent.model, runnerTags: agent.runnerTags, status: agent.status.word,
            figure: AgentLook.figure(agent.figureState.word), paletteID: agent.appearance.paletteId,
            avatarPath: agent.avatarUrl, reportsTo: agent.reportsTo)
    }
}

extension DepartmentInfo {
    init(_ department: Schemas.Department) {
        self.init(
            id: department.id, name: department.name,
            teams: department.teams.map { team in
                TeamInfo(
                    id: team.id, name: team.name,
                    seats: team.members.map { SeatInfo(agentID: $0.agentId, teamRole: $0.teamRole.word) })
            })
    }
}

extension RunInfo {
    init(_ run: Schemas.Run) {
        self.init(
            id: run.id, agentID: run.agentId, issueID: run.issueId, state: run.state.word, harness: run.harness.word,
            harnessVersion: run.harnessVersion, model: run.modelUsed, accountID: run.accountId, runnerID: run.runnerId,
            fallbackReason: run.fallbackReason, terminalReason: run.terminalReason,
            inputTokens: run.usage.inputTokens, outputTokens: run.usage.outputTokens,
            cacheTokens: run.usage.cacheTokens, costMicros: run.usage.costUsdMicros, contextTokens: run.contextTokens,
            queuedAt: run.queuedAt, wokenAt: run.wokenAt, claimedAt: run.claimedAt, startedAt: run.startedAt,
            harnessStartedAt: run.harnessStartedAt, firstTokenAt: run.firstTokenAt, endedAt: run.endedAt,
            lastProgressAt: run.lastProgressAt, diffRepos: run.diffRepos.map(RepoDiffInfo.init))
    }
}

extension IssueInfo {
    init(_ issue: Schemas.Issue) {
        let next: NextActorInfo? =
            switch issue.nextActor {
            case .agent(let a): .agent(a.agentId)
            case .human: .human
            case .timer(let t): .timer(t.at)
            case nil: nil
            }
        self.init(
            id: issue.id, key: issue.key, title: issue.title, projectID: issue.projectId,
            requirementID: issue.requirementId, state: issue.state.word, nextActor: next,
            points: issue.points.map(Int.init))
    }
}

extension ApprovalInfo {
    init(_ approval: Schemas.Approval) {
        let payload = approval.payload.value
        var lists: [String: [[String: String]]] = [:]
        var fields = flatFields(payload)
        for (key, value) in payload {
            guard let rows = value as? [(any Sendable)?] else { continue }
            let objects = rows.compactMap { $0 as? [String: (any Sendable)?] }
            if objects.isEmpty {
                // A list of words (`runner_tags`): one field, space-separated.
                fields[key] = rows.compactMap { $0 as? String }.joined(separator: " ")
            } else {
                lists[key] = objects.map { flatFields($0) }
            }
        }
        self.init(
            id: approval.id, kind: approval.kind.word, agentID: approval.agentId, issueID: approval.issueId,
            requestedBy: approval.requestedBy, expiresAt: approval.expiresAt,
            fields: fields, status: approval.status.word, reply: approval.reply,
            sprintID: approval.sprintId, lists: lists)
    }
}

extension QuestionInfo {
    init(_ question: Schemas.Question) {
        self.init(
            id: question.id, agentID: question.askedByAgentId, issueID: question.issueId, issueKey: question.issueKey,
            requirementID: question.requirementId, runID: question.runId, text: question.question,
            options: question.options, state: question.state.word, askedAt: question.createdAt)
    }
}

extension CommentInfo {
    init(_ comment: Schemas.Comment) {
        let agent: Int64? =
            switch comment.author {
            case .agent(let a): a.agentId
            case .human: nil
            }
        self.init(id: comment.id, issueID: comment.issueId, agentID: agent, body: comment.body, runID: comment.runId)
    }
}

extension StuckInfo {
    init(_ stuck: Schemas.StuckIssue) {
        self.init(
            kind: stuck.kind.word, issueID: stuck.issueId, agentID: stuck.agentId, reason: stuck.reason,
            action: stuck.action, repair: stuck.repair.word, lastRepair: stuck.lastRepair?.action,
            lastRepairAt: stuck.lastRepair?.at, since: stuck.stuckSince)
    }
}

extension RequirementInfo {
    init(_ requirement: Schemas.Requirement, tree: Schemas.RequirementTree? = nil) {
        self.init(
            id: requirement.id, key: requirement.key, title: requirement.title, state: requirement.state.word,
            ownerAgentID: requirement.ownerAgentId, points: Int(tree?.points ?? 0),
            donePoints: Int(tree?.donePoints ?? 0), percentDone: Int(tree?.percentDone ?? 0), eta: tree?.eta)
    }
}

extension BudgetInfo {
    init(_ budget: Schemas.BudgetStanding, label: (String) -> String) {
        let scope: String =
            switch budget.scope {
            case .agent(let s): "agent:\(s.agentId)"
            case .company(let s): "company:\(s.companyId)"
            case .department(let s): "department:\(s.departmentId)"
            case .project(let s): "project:\(s.projectId)"
            case .sprint(let s): "sprint:\(s.sprintId)"
            }
        self.init(
            id: budget.budgetId, label: label(scope), scope: scope, period: budget.period.word,
            periodKey: budget.periodKey, spent: budget.spent, cap: budget.tokenCap + budget.raised,
            warnPercent: Int(budget.warnAtPercent), raised: budget.raised, hardStop: budget.hardStop)
    }
}

extension SpendInfo {
    init(_ report: Schemas.CostReport) {
        let all = report.inputTokens + report.outputTokens + report.cacheTokens
        self.init(
            costMicros: report.costUsdMicros, runs: report.runs, pricedRuns: report.pricedRuns,
            unpricedRuns: report.unpricedRuns, unpricedTokens: report.unpricedTokens,
            subscriptionRuns: report.subscriptionRuns, subscriptionTokens: report.subscriptionTokens,
            pricedTokens: max(0, all - report.unpricedTokens - report.subscriptionTokens))
    }
}

extension AccountInfo {
    init(_ account: Schemas.Account, usage: Schemas.AccountUsage?) {
        let fullest = usage?.limits.max {
            Double($0.used) / Double(max($0.limit.max, 1)) < Double($1.used) / Double(max($1.limit.max, 1))
        }
        self.init(
            id: account.id, label: account.label, billing: account.billing.word, status: account.status.word,
            statusReason: account.statusReason,
            statusUntil: account.statusUntil,
            windowUse: fullest.map { Double($0.used) / Double(max($0.limit.max, 1)) },
            windowSecs: fullest?.limit.windowSecs, warnPercent: fullest?.limit.warnPercent)
    }
}

extension TranscriptChunkInfo {
    init(_ chunk: Schemas.TranscriptChunk) {
        self.init(seq: chunk.seq, at: chunk.at, kind: chunk.kind, fields: flatFields(chunk.payload.value))
    }
}

/// A JSON object's scalar fields as text, one level of nesting as `parent.key` (a tool's `input.command`).
func flatFields(_ object: [String: (any Sendable)?], prefix: String = "") -> [String: String] {
    var out: [String: String] = [:]
    for (key, value) in object {
        let name = prefix.isEmpty ? key : "\(prefix).\(key)"
        switch value {
        case let text as String: out[name] = text
        case let flag as Bool: out[name] = flag ? "true" : "false"
        case let number as Int: out[name] = String(number)
        case let number as Int64: out[name] = String(number)
        case let number as Double: out[name] = number.rounded() == number ? String(Int64(number)) : String(number)
        case let nested as [String: (any Sendable)?] where prefix.isEmpty:
            out.merge(flatFields(nested, prefix: name)) { a, _ in a }
        default: break
        }
    }
    return out
}
