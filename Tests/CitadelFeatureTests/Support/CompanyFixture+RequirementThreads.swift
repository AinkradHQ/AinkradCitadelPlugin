import Foundation

@testable import CitadelFeature

/// The prototype's other requirement threads (`reqs.js` REQ_THREADS / REQ_PLANS): R-11's plan waiting for you,
/// R-9 with the CEO drafting, and R-7 delivered.
@MainActor
extension CompanyFixture {
    static func otherRequirements(_ model: CompanyModel) {
        let page = model.requirementsPage
        let today = now.addingTimeInterval(-50 * 60)
        func you(_ id: Int64, _ issue: Int64, _ body: String, _ at: Date) -> ThreadItem {
            .message(CommentInfo(id: id, issueID: issue, agentID: nil, body: body, runID: nil), at: at)
        }
        func agent(_ id: Int64, _ issue: Int64, _ who: Int64, _ body: String, _ at: Date) -> ThreadItem {
            .message(CommentInfo(id: id, issueID: issue, agentID: who, body: body, runID: nil), at: at)
        }
        // R-11 · plan to approve.
        page.threads[11] = RequirementThread(
            requirementID: 11, ownerAgentID: 3, toQuestionID: nil,
            items: [
                you(
                    40, 80,
                    "Every approval I give or deny should be in an audit log I can search later — who asked, what I decided, why.",
                    today),
                agent(
                    41, 80, 1,
                    "Routed to Engineering › Citadel Core. Mira drafted the plan with Toma: 2 epics, 5 tasks, 13 pts. Nothing starts until you approve it.",
                    today.addingTimeInterval(7 * 60)),
                .approval(
                    ApprovalInfo(
                        id: 30, kind: "plan_approval", agentID: nil, issueID: nil, requestedBy: 3, expiresAt: nil,
                        fields: ["requirement": "11", "key": "R-11", "title": "Audit log of approvals", "points": "13"]),
                    at: today.addingTimeInterval(9 * 60)),
            ])
        func todo(_ id: Int64, _ key: String, _ title: String, agent: Int64, points: Int) -> PlanTask {
            PlanTask(
                issueID: id, key: key, title: title, points: points, state: "todo", assigneeAgentID: agent, prs: 0,
                timeSecs: 0, tokens: 0, sprintID: nil)
        }
        page.plans[11] = PlanTree(
            points: 13, donePoints: 0, percent: 0, tasks: 5, doneTasks: 0, eta: nil, pointsPerDay: 0, tokens: 0,
            costMicros: 0, burndown: [],
            epics: [
                PlanEpic(
                    id: 11, projectID: 1, title: "Audit store", points: 6, donePoints: 0,
                    tasks: [
                        todo(270, "CIT-70", "Approval events table", agent: 4, points: 3),
                        todo(271, "CIT-71", "Search API", agent: 5, points: 3),
                    ]),
                PlanEpic(
                    id: 12, projectID: 1, title: "Audit UI", points: 7, donePoints: 0,
                    tasks: [
                        todo(272, "CIT-72", "Audit log screen", agent: 11, points: 5),
                        todo(273, "CIT-73", "Export CSV", agent: 5, points: 1),
                        todo(274, "CIT-74", "QA pass", agent: 9, points: 1),
                    ]),
            ], other: [], diff: nil, intakeIssueID: 80, planVersion: 0)
        // R-9 · drafting: Aldric's run on the intake issue is live.
        page.threads[9] = RequirementThread(
            requirementID: 9, ownerAgentID: 1, toQuestionID: nil,
            items: [
                you(
                    50, 90,
                    "Quest should read issues and sprints from the Citadel server instead of local files when a project is linked.",
                    now.addingTimeInterval(-3 * 3600)),
                agent(
                    51, 90, 1,
                    "Drafting. I'm checking with Vesper whether this belongs to Citadel Core or needs a Quest team first — no work starts until there's a plan for you.",
                    now.addingTimeInterval(-3 * 3600 + 11 * 60)),
            ])
        model.issues[90] = IssueInfo(id: 90, key: "CIT-75", title: "R-9 intake", projectID: 1, requirementID: 9)
        model.runs[440] = run(440, agent: 1, issue: 90, minutes: 2, tokens: 9_000, model: "opus-5.5")
        // R-7 · done.
        page.threads[7] = RequirementThread(
            requirementID: 7, ownerAgentID: 1, toQuestionID: nil,
            items: [
                you(
                    60, 95, "Show me the org chart and let agents propose hires that I approve.",
                    now.addingTimeInterval(-13 * 86_400)),
                agent(
                    61, 95, 1,
                    "Done and shipped in Citadel 1.0 — the Org screen and hire approvals. Closing this requirement.",
                    now.addingTimeInterval(-6 * 86_400)),
            ])
    }
}
