import AinkradAppKit
import SwiftUI

/// Screen 12's prototype actions: approve a plan or send it back with a reason, from the hero, the plan card or the
/// drawer; answer an ask; send a new requirement — each confirmed with a toast. No Undo: a decided approval can't
/// be reversed on the server (plan decision 2).
extension CitadelStore {
    /// Approve plan: the approval is decided; work starts as its tasks are scheduled.
    func approvePlan(_ approval: ApprovalInfo, requirement: RequirementInfo) {
        decide(approval, approve: true)
        model?.requirementsPage.askingChanges = false
        let owner = model?.agent(requirement.ownerAgentID)
        toast(
            AinkradRichToast(
                title: "\(requirement.key) plan approved",
                body: "\(owner?.name ?? "The PO") schedules its tasks — agents wake as their tasks start.",
                status: .success, icon: icon(owner)))
    }

    /// Ask for changes: the plan approval is sent back with your reason, which reaches the PO.
    func askForChanges(requirement: RequirementInfo, reason: String) {
        guard let model else { return }
        let approval =
            model.approvals.first {
                $0.kind == "plan_approval" && $0.fields["requirement"] == String(requirement.id)
            }
            ?? model.requirementsPage.threads[requirement.id]?.items.lazy.compactMap { item -> ApprovalInfo? in
                if case .approval(let a, _) = item, a.kind == "plan_approval", a.status == "pending" { return a }
                return nil
            }.first
        guard let approval else { return }
        let text = reason.trimmingCharacters(in: .whitespacesAndNewlines)
        decide(approval, approve: false, reply: text.isEmpty ? "Please revise the plan." : text)
        model.requirementsPage.askingChanges = false
        let owner = model.agent(requirement.ownerAgentID)
        toast(
            AinkradRichToast(
                title: "Sent back to \(owner?.name ?? "the PO")",
                body: "A revised plan comes back to you with a diff to approve.", status: .neutral,
                icon: icon(owner)))
    }

    /// A quick reply or composer answer to an agent's question: routed to the asker, who wakes.
    func answer(_ text: String, question: QuestionInfo, requirement: Int64) {
        send(text, requirement: requirement, to: .question(question))
        let asker = model?.agent(question.agentID)
        toast(
            AinkradRichToast(
                title: "Answer routed to \(asker?.name ?? "the agent")", body: "on \(question.issueKey) · it wakes now",
                status: .success, icon: icon(asker)))
    }

    /// The New requirement sheet's send: the request goes to the CEO, who routes it.
    func sendNewRequirement(title: String, body: String, extras: RequestExtras? = nil) {
        submitRequirement(title: title, body: body, extras: extras)
        isComposingRequirement = false
        screen = .requirements
        detail = nil
        let ceo = model?.ceo
        toast(
            AinkradRichToast(
                title: "Sent to \(ceo?.name ?? "the CEO")", body: "Routing it — the plan comes back to you.",
                status: .success, icon: icon(ceo)))
    }

    private func icon(_ agent: AgentInfo?) -> AnyView? {
        guard let agent, let model else { return nil }
        return AnyView(AgentFigure(agent: agent, model: model, size: 28))
    }
}
