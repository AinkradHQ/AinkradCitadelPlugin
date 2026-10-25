import CitadelClient
import Foundation

@testable import CitadelFeature

extension CompanyFixture {
    /// What a server at API minor 18 adds to a screen, for the sweeps: dollar budgets, an unpriced model, chain
    /// presets with agents on them, roles, an agent's stats and the notification matrix.
    static func trancheB(_ model: CompanyModel) {
        model.budgets = model.budgets.map { budget in
            var budget = budget
            switch budget.scope {
            case "company:1":
                budget.cap = 0
                budget.usdCap = 900_000_000
                budget.usdSpent = 412_000_000
            case "department:2":
                budget.cap = 0
                budget.usdCap = 120_000_000
                budget.usdSpent = 98_000_000
            default: break
            }
            return budget
        }
        model.unpriced = [
            UnpricedModelInfo(harness: "opencode", model: "qwen3-coder", runs: 12, tokens: 2_100_000),
            UnpricedModelInfo(harness: "agy", model: "gemini-3-flash", runs: 3, tokens: 240_000),
        ]
        model.chainPresets = [
            ChainPresetInfo(
                id: 1, name: "Codex first", description: "gpt-5.5, then Opus, then the free model",
                colorHex: "#2563eb", isDefault: true,
                entries: [
                    FallbackEntry(harness: "codex", model: "gpt-5.5", accountID: 4),
                    FallbackEntry(harness: "claude", model: "opus-5.5"),
                    FallbackEntry(harness: "opencode", model: "qwen3-coder"),
                ]),
            ChainPresetInfo(
                id: 2, name: "Claude first", description: "Sonnet, Opus, then Codex", colorHex: "#a855f7",
                isDefault: false,
                entries: [
                    FallbackEntry(harness: "claude", model: "sonnet-5"),
                    FallbackEntry(harness: "claude", model: "opus-5.5"),
                    FallbackEntry(harness: "codex", model: "gpt-5.5"),
                ]),
            ChainPresetInfo(
                id: 3, name: "Cheap and cheerful", description: "", colorHex: "#10b981", isDefault: false,
                entries: [
                    FallbackEntry(harness: "opencode", model: "qwen3-coder"),
                    FallbackEntry(harness: "agy", model: "gemini-3-flash"),
                ]),
        ]
        for (index, id) in model.agents.keys.sorted().enumerated() {
            model.agents[id]?.chainPresetID = [1, 1, 2, 2, nil, 3][index % 6]
        }
        model.agents[14]?.queuedWakes = 3
        model.roles = HireCatalog.roles.enumerated().map { index, role in
            RoleInfo(
                id: Int64(index + 1), name: role.name, purpose: role.purpose, icon: role.symbol, skills: [],
                instructions: role.instructions, harness: role.harness, model: role.model, budgetTokens: role.budget)
        }
        model.notifications = NotificationPrefs(
            matrix: [
                "approval_waiting|push": true, "approval_waiting|signal": true, "run_waiting_permission|push": true,
                "agent_question|push": true, "agent_question|email": true, "issue_stuck|push": true,
                "budget_warning|push": true, "budget_warning|email": true, "account_limit|signal": true,
                "requirement_done|push": true,
            ], quietStart: 1320, quietEnd: 450, quietOn: true, breakthrough: "stalled")
        model.agentStats[4] = try? EventFrame.decoder.decode(
            Schemas.AgentStats.self,
            from: Data(
                """
                {"avg_cost_micros":1280000,
                 "runs_by_day":[\(days(by: [0, 1, 3, 2, 4, 1, 2]))],
                 "success_by_week":[{"week":"2026-08-31","runs":6,"succeeded":5},{"week":"2026-09-07","runs":8,"succeeded":7},
                   {"week":"2026-09-14","runs":5,"succeeded":5},{"week":"2026-09-21","runs":9,"succeeded":6},
                   {"week":"2026-09-28","runs":7,"succeeded":7},{"week":"2026-10-05","runs":10,"succeeded":8},
                   {"week":"2026-10-12","runs":9,"succeeded":9},{"week":"2026-10-19","runs":4,"succeeded":3}],
                 "heatmap":[[0,2,5,6,3,0],[0,1,4,7,5,1],[0,3,6,6,4,0],[0,2,5,8,3,2],[0,1,3,4,2,0],[0,0,1,0,0,0],[0,0,0,1,0,0]],
                 "daily_spend":[\(spend())]}
                """.utf8))
    }

    /// `runs_by_day` rows for the seven days ending today (UTC).
    private static func days(by runs: [Int]) -> String {
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        format.timeZone = TimeZone(identifier: "UTC")
        return runs.enumerated().map { index, count in
            let day = format.string(from: Date().addingTimeInterval(Double(index - 6) * 86_400))
            return #"{"day":"\#(day)","runs":\#(count)}"#
        }.joined(separator: ",")
    }

    /// `daily_spend` rows for each day of this month so far.
    private static func spend() -> String {
        let calendar = Calendar.current
        let today = calendar.component(.day, from: Date())
        let format = DateFormatter()
        format.dateFormat = "yyyy-MM-dd"
        return (1...today).map { day in
            let date = calendar.date(byAdding: .day, value: day - today, to: Date()) ?? Date()
            return
                #"{"day":"\#(format.string(from: date))","cost_usd_micros":\#(2_000_000 + day * 150_000),"tokens":\#(90_000 + day * 6_000)}"#
        }.joined(separator: ",")
    }
}
