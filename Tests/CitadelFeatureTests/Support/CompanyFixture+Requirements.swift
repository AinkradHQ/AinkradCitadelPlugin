import AppKit
import Foundation

@testable import CitadelFeature

/// Screens 12 and 13 as the mockups show them: R-12 with the CEO, Kestrel's open .p8 question on CIT-62, Wren's
/// answered one, Sable's QA + merge card and artifacts, and the live plan.
@MainActor
extension CompanyFixture {
    static let qaReport = """
        #### QA — CIT-61 runner lease heartbeat
        Verdict: **pass** · 6 of 6 acceptance checks

        ##### Checks
        | Case | Before | After |
        | --- | --- | --- |
        | Runner killed mid-run | lost silently | runner_lost in 30 s |
        | Network blip 10 s | run aborted | lease kept |
        | Clock skew 2 min | ok | ok |

        ##### Evidence
        lease-expired.png, lease-renewed.png — attached to this report.
        """

    static func requirementsPage(_ model: CompanyModel) {
        func requirement(
            _ id: Int64, _ title: String, _ state: String, owner: Int64, points: Int, done: Int
        ) -> RequirementInfo {
            RequirementInfo(
                id: id, key: "R-\(id)", title: title, state: state, ownerAgentID: owner, points: points,
                donePoints: done, percentDone: points == 0 ? 0 : done * 100 / points, eta: nil)
        }
        model.requirements = [
            requirement(12, "Phone alerts when I'm needed", "in_progress", owner: 1, points: 31, done: 5),
            requirement(11, "Audit log of approvals", "plan_review", owner: 3, points: 13, done: 0),
            requirement(10, "Launch blog post for 1.0", "in_progress", owner: 14, points: 7, done: 5),
            requirement(9, "Quest reads from the server", "planning", owner: 1, points: 0, done: 0),
            requirement(8, "Never miss events on reconnect", "in_progress", owner: 3, points: 18, done: 15),
            requirement(7, "Org chart + hiring flow", "done", owner: 1, points: 21, done: 21),
        ]
        model.approvals.append(
            ApprovalInfo(
                id: 30, kind: "plan_approval", agentID: nil, issueID: nil, requestedBy: 3, expiresAt: nil,
                fields: ["requirement": "11", "key": "R-11", "title": "Audit log of approvals", "points": "13"]))
        for (id, key, title) in [
            (Int64(54), "CIT-54", "Notification events"), (60, "CIT-60", "Push for blocked work"),
            (62, "CIT-62", "APNs push sender"), (58, "CIT-58", "Device registration"),
            (63, "CIT-63", "List + revoke keys"), (66, "CIT-66", "Rate limits on auth"),
            (116, "AMC-16", "Alert settings pane"), (117, "AMC-17", "Deep link to approval"),
            (70, "CIT-70", "R-12 intake"),
        ] {
            model.issues[id] = IssueInfo(id: id, key: key, title: title, projectID: 1, requirementID: 12)
        }
        for id in [Int64(61), 57] { model.issues[id]?.requirementID = 12 }
        model.issueRepos[62] = ["citadel", "ainkrad-citadel-plugin"]
        let kestrel = QuestionInfo(
            id: 7, agentID: 4, issueID: 62, issueKey: "CIT-62", requirementID: 12, runID: nil,
            text:
                "For APNs: should I use a **.p8 token key** (one key for every app, never expires) or a **.p12 certificate** per app (expires yearly)? Either way you need to create it in the Apple developer account — I can't.",
            options: [".p8 token key — I'll upload it", ".p12 certificate", "Ask Toma to decide"], state: "open",
            askedAt: now.addingTimeInterval(-4 * 60))
        var wren = QuestionInfo(
            id: 5, agentID: 5, issueID: 58, issueKey: "CIT-58", requirementID: 12, runID: nil,
            text: "does revoke kill live runs?", options: [], state: "answered",
            askedAt: now.addingTimeInterval(-2 * 86_400))
        wren.state = "answered"
        model.questions = [kestrel]
        let day = now.addingTimeInterval(-3 * 86_400)
        for (id, hue) in [(Int64(102), 0.55), (103, 0.42), (107, 0.6)] {
            model.artifactsPage.images[id] = shot(hue: hue)
        }
        let page = model.requirementsPage
        page.isLoaded = true
        page.selectedID = 12
        page.threads[12] = RequirementThread(
            requirementID: 12, ownerAgentID: 1, toQuestionID: 7,
            items: [
                .message(
                    CommentInfo(
                        id: 1, issueID: 70, agentID: nil,
                        body:
                            "I want my phone to buzz when something needs me — approvals, blocked work, a budget hitting its line. Not every run event.",
                        runID: nil), at: day),
                .message(
                    CommentInfo(
                        id: 2, issueID: 70, agentID: 1,
                        body:
                            "Routed to Engineering. Mira (PO) and Toma (Lead) drafted the full plan before any work starts — 3 epics, 9 tasks, 28 pts, about 5 days. Citadel's policy says you approve plans.",
                        runID: nil), at: day.addingTimeInterval(19 * 60)),
                .approval(
                    ApprovalInfo(
                        id: 31, kind: "plan_approval", agentID: nil, issueID: nil, requestedBy: 3, expiresAt: nil,
                        fields: ["requirement": "12", "key": "R-12", "points": "28"], status: "approved",
                        lists: ["tasks": (1...9).map { ["key": "CIT-\($0)", "epic": "\($0 % 3)"] }]),
                    at: day.addingTimeInterval(52 * 60)),
                .question(wren, answer: "yes, end them"),
                .message(
                    CommentInfo(
                        id: 3, issueID: 61, agentID: 9,
                        body:
                            "Lease heartbeat verified across both repos — the server expires the lease, the plugin shows it. Report and the failing-then-passing screenshots are attached.",
                        runID: 428), at: now.addingTimeInterval(-40 * 60)),
                .approval(
                    ApprovalInfo(
                        id: 22, kind: "pr_merge", agentID: nil, issueID: 61, requestedBy: 9, expiresAt: nil,
                        fields: ["summary": "Merge 2 PRs"],
                        lists: [
                            "prs": [
                                ["repo": "citadel", "pr": "61"], ["repo": "ainkrad-citadel-plugin", "pr": "14"],
                            ]
                        ]), at: now.addingTimeInterval(-39 * 60)),
                .artifact(artifacts[0]),
                .artifact(artifacts[1]),
                .question(kestrel, answer: nil),
            ])
        func task(
            _ issue: Int64, _ key: String, _ title: String, _ state: String, agent: Int64, points: Int,
            prs: Int64 = 0, time: Int64 = 0, tokens: Int64 = 0
        ) -> PlanTask {
            PlanTask(
                issueID: issue, key: key, title: title, points: points, state: state, assigneeAgentID: agent, prs: prs,
                timeSecs: time, tokens: tokens, sprintID: 4)
        }
        page.plans[12] = PlanTree(
            points: 31, donePoints: 5, percent: 16, tasks: 10, doneTasks: 2, eta: "2026-10-27", pointsPerDay: 2.5,
            tokens: 312_000, costMicros: 14_200_000,
            burndown: [("2026-10-19", 28), ("2026-10-20", 27), ("2026-10-21", 25), ("2026-10-22", 26)],
            epics: [
                PlanEpic(
                    id: 1, projectID: 1, title: "APNs delivery", points: 17, donePoints: 3,
                    tasks: [
                        task(
                            54, "CIT-54", "Notification events", "done", agent: 4, points: 3, time: 6000, tokens: 96_000
                        ),
                        task(61, "CIT-61", "Lease heartbeat", "in_review", agent: 8, points: 3, prs: 2),
                        task(62, "CIT-62", "APNs push sender", "todo", agent: 4, points: 8),
                        task(60, "CIT-60", "Push for blocked work", "blocked", agent: 4, points: 3),
                    ]),
                PlanEpic(
                    id: 2, projectID: 1, title: "Device keys", points: 9, donePoints: 2,
                    tasks: [
                        task(
                            58, "CIT-58", "Device registration", "done", agent: 5, points: 2, time: 3000, tokens: 40_000
                        ),
                        task(57, "CIT-57", "QA: rate-limit auth", "in_progress", agent: 9, points: 2),
                        task(63, "CIT-63", "List + revoke keys", "todo", agent: 5, points: 3),
                        task(66, "CIT-66", "Rate limits on auth", "todo", agent: 5, points: 2),
                    ]),
                PlanEpic(
                    id: 3, projectID: 2, title: "Mac client alerts", points: 5, donePoints: 0,
                    tasks: [
                        task(116, "AMC-16", "Alert settings pane", "todo", agent: 11, points: 3),
                        task(117, "AMC-17", "Deep link to approval", "todo", agent: 11, points: 2),
                    ]),
            ],
            other: [],
            diff: PlanDiffInfo(
                version: 1, added: [("CIT-60", 3)], removed: [], pointsApproved: 28, pointsNow: 31),
            intakeIssueID: 70, planVersion: 1)
        for (index, key) in ["CIT-E1", "CIT-E2", "AMC-E1"].enumerated() { page.plans[12]?.epics[index].key = key }
    }

    static var artifacts: [ArtifactInfo] {
        func artifact(
            _ id: Int64, _ name: String, _ kind: String, mime: String, size: Int64, preview: String, agent: Int64,
            issue: Int64?, requirement: Int64? = 12, run: Int64? = nil, ago: TimeInterval
        ) -> ArtifactInfo {
            ArtifactInfo(
                id: id, name: name, kind: kind, mime: mime, size: size, preview: preview,
                sha256: "9f2c4b7d1e0a3c5f6b8d9e0f1a2b3c4d5e6f7a8b9c0d1e2f3a4b5c6d7e8f90e1", agentID: agent,
                issueID: issue, requirementID: requirement, runID: run, createdAt: now.addingTimeInterval(-ago),
                redactions: 0)
        }
        return [
            artifact(
                101, "qa-report-cit-61.md", "report", mime: "text/markdown", size: 2_100, preview: "text", agent: 9,
                issue: 61, run: 428, ago: 30 * 60),
            artifact(
                102, "lease-expired.png", "screenshot", mime: "image/png", size: 182_000, preview: "image", agent: 9,
                issue: 61, requirement: nil, run: 428, ago: 31 * 60),
            artifact(
                103, "lease-renewed.png", "screenshot", mime: "image/png", size: 176_000, preview: "image", agent: 9,
                issue: 61, requirement: nil, run: 428, ago: 32 * 60),
            artifact(
                104, "apns-design-note.md", "report", mime: "text/markdown", size: 3_400, preview: "text", agent: 4,
                issue: 62, ago: 60 * 60),
            artifact(
                105, "r-12-plan-v1.md", "report", mime: "text/markdown", size: 5_200, preview: "text", agent: 3,
                issue: nil, ago: 3 * 86_400),
            artifact(
                106, "rate-limit-soak.log", "file", mime: "text/plain", size: 84_000, preview: "none", agent: 9,
                issue: 57, ago: 2 * 86_400),
            artifact(
                107, "device-keys-list.png", "screenshot", mime: "image/png", size: 140_000, preview: "image",
                agent: 5, issue: 58, ago: 2 * 86_400 + 60),
            artifact(
                108, "notification-events.json", "file", mime: "application/json", size: 6_000, preview: "none",
                agent: 4, issue: 54, ago: 2 * 86_400 + 120),
            artifact(
                109, "qa-report-cit-58.md", "report", mime: "text/markdown", size: 1_800, preview: "text", agent: 9,
                issue: 58, ago: 2 * 86_400 + 180),
        ]
    }

    static func artifactsPage(_ model: CompanyModel) {
        requirementsPage(model)
        let page = model.artifactsPage
        page.isLoaded = true
        page.items = artifacts
        page.usage = ArtifactUsageInfo(used: 212_000_000, quota: 2_000_000_000, maxFile: 10_000_000)
        page.filter = ArtifactFilter(requirementID: 12)
        page.selectedID = 101
        page.texts[101] = qaReport
        page.texts[104] = "## APNs design note\nToken-based auth with a .p8 key; one key, every app.\n- sandbox first"
        page.texts[105] = "# R-12 plan v1\n3 epics · 9 tasks · 28 pts\n- APNs delivery\n- Device keys\n- Mac alerts"
        page.texts[109] = "#### QA — CIT-58 device registration\nVerdict: pass · 4 of 4 checks"
        model.runs[428] = ended(428, issue: 61, state: "succeeded", daysAgo: 0.03, minutes: 9, cost: 600_000)
    }

    /// A stand-in screenshot: a window with a sidebar and a card.
    static func shot(hue: Double) -> NSImage {
        NSImage(size: NSSize(width: 1440, height: 900), flipped: false) { rect in
            NSColor(calibratedWhite: 0.08, alpha: 1).setFill()
            rect.fill()
            NSColor(calibratedHue: 0.62, saturation: 0.7, brightness: 0.45, alpha: 1).setFill()
            NSRect(x: 0, y: 0, width: rect.width * 0.28, height: rect.height).fill()
            NSColor(calibratedHue: hue, saturation: 0.6, brightness: 0.45, alpha: 1).setFill()
            NSRect(x: rect.width * 0.36, y: rect.height * 0.45, width: rect.width * 0.55, height: rect.height * 0.3)
                .fill()
            return true
        }
    }
}
