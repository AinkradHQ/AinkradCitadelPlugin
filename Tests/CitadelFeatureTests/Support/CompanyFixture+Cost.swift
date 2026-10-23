import AinkradAppKit
import Foundation

@testable import CitadelFeature

/// Screens 08 and 09 of the mockups' company: why stuck, and cost.
@MainActor
extension CompanyFixture {
    static func stuckPage(_ model: CompanyModel) {
        for issue in [
            IssueInfo(
                id: 49, key: "CIT-49", title: "Knowledge injection size budget", projectID: 1, requirementID: nil),
            IssueInfo(id: 55, key: "CIT-55", title: "SQLite busy timeout under load", projectID: 1, requirementID: nil),
            IssueInfo(id: 58, key: "CIT-58", title: "Escalation chain skips CEO", projectID: 1, requirementID: nil),
            IssueInfo(id: 60, key: "CIT-60", title: "Push for blocked work", projectID: 1, requirementID: nil),
        ] { model.issues[issue.id] = issue }
        model.stuck = [
            StuckInfo(
                kind: "run_queued_no_lease", issueID: 49, agentID: 8, reason: "runner lost, retries used up",
                action: "Rook's run #409 ended runner_lost on hetzner-2 and the retry was lost too",
                repair: "reassign_to_lead", lastRepair: "requeue", lastRepairAt: now.addingTimeInterval(-3_600)),
            StuckInfo(
                kind: "wake_no_runner", issueID: 9, agentID: 11, reason: "needs a macos runner; the only one is asleep",
                action: "ahmed-mbp went to sleep at 01:40; the issue is queued and Pike is idle waiting for it",
                repair: "notify", lastRepair: nil, lastRepairAt: nil),
            StuckInfo(
                kind: "agent_paused_by_breaker", issueID: 55, agentID: 4, reason: "loop breaker tripped",
                action: "Kestrel failed 3 times with the same fingerprint; the engine stopped it and escalated",
                repair: "escalate", lastRepair: "escalate", lastRepairAt: now.addingTimeInterval(-2_880)),
            StuckInfo(
                kind: "reviewer_inactive", issueID: 58, agentID: 9, reason: "reviewer paused",
                action: "the QA step is assigned to Sable, but Sable's queue has 4 items ahead",
                repair: "reassign_to_lead", lastRepair: nil, lastRepairAt: nil),
            StuckInfo(
                kind: "in_progress_idle", issueID: 60, agentID: 5, reason: "no progress for a day",
                action: "it waits on CIT-62 (APNs push), which needs an Apple push key from you",
                repair: "rewake", lastRepair: "rewake", lastRepairAt: now.addingTimeInterval(-7_200)),
        ]
    }

    static func costPage(_ model: CompanyModel) {
        func task(
            _ id: Int64, _ key: String, _ title: String, tokens: Int64, sub: Int64 = 0, unpriced: Int64 = 0,
            usd: Double, secs: Int64
        ) -> TaskCostInfo {
            TaskCostInfo(
                issueID: id, key: key, title: title, tokens: tokens, unpricedTokens: unpriced, subscriptionTokens: sub,
                costMicros: Int64(usd * 1_000_000), secs: secs, runs: 3, pricedRuns: usd > 0 ? 2 : 0,
                unpricedRuns: unpriced > 0 ? 1 : 0, subscriptionRuns: sub > 0 ? 2 : 0)
        }
        model.costTasks = [
            task(42, "CIT-42", "Event stream replay", tokens: 164_000, usd: 1.90, secs: 11_400),
            task(62, "CIT-62", "APNs push sender", tokens: 148_000, sub: 148_000, usd: 0, secs: 7_800),
            task(8, "MKT-8", "Launch blog post", tokens: 121_000, usd: 4.20, secs: 5_100),
            task(61, "CIT-61", "Lease heartbeat", tokens: 96_000, sub: 96_000, usd: 0, secs: 6_000),
            task(74, "CIT-74", "Bump sqlx", tokens: 9_000, usd: 0.04, secs: 360),
            task(12, "AMC-12", "Citadel plugin scaffold", tokens: 2_100_000, unpriced: 2_100_000, usd: 0, secs: 9_000),
        ]
        let shape: [(Int64, Int64, Int64)] = [
            (9, 0, 6), (12, 0, 8), (14, 1, 7), (11, 0, 9), (6, 0, 4), (3, 0, 2), (15, 2, 9), (18, 0, 11), (17, 1, 8),
            (20, 0, 12), (16, 0, 9), (5, 0, 3), (4, 0, 2), (22, 3, 10), (24, 0, 13), (19, 2, 11), (21, 0, 12),
            (25, 4, 14), (7, 0, 4), (6, 0, 3), (23, 2, 12), (18, 1, 9),
        ]
        let start = Calendar.current.startOfDay(for: now).addingTimeInterval(-Double(shape.count - 1) * 86_400)
        model.costDays = shape.enumerated().map { index, day in
            DaySpend(
                day: start.addingTimeInterval(Double(index) * 86_400),
                totals: SpendTotals(
                    costMicros: day.0 * 1_000_000, pricedTokens: day.0 * 20_000, unpricedTokens: day.1 * 20_000,
                    subscriptionTokens: day.2 * 20_000))
        }
        model.accounts[1]?.billing = "subscription"
        model.accounts[2]?.billing = "subscription"
        model.accounts[3] = AccountInfo(id: 3, label: "anthropic-api", status: "active")
        model.accountUse = [
            AccountUseInfo(id: 1, label: "claude-work", tokens: 6_100_000, runs: 40),
            AccountUseInfo(id: 2, label: "codex-pro", tokens: 8_300_000, runs: 52),
            AccountUseInfo(id: 3, label: "anthropic-api", tokens: 3_400_000, runs: 61),
        ]
        model.costPeriod = .month
    }
}
