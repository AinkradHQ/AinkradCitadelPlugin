import Foundation

/// The hire wizard's and the agent drawer's choices (prototype `hire.js`). The server has no roles resource, no
/// model catalog and no sandbox / effort / guidelines on an agent yet (spec 03 §4.3), so these are client
/// templates: a role only fills in defaults the person can change before proposing.
enum HireCatalog {
    struct Role: Identifiable, Equatable {
        var id: String { name }
        let name: String
        let purpose: String
        let symbol: String
        let harness: String
        let model: String
        /// Month budget, tokens (decision 1: budgets in tokens until the server stores dollars).
        let budget: Int64
        let instructions: String
    }

    struct Model: Identifiable, Equatable {
        var id: String { wire }
        let wire: String
        let name: String
        let blurb: String
        let quality: Int
        let speed: Int
        let cost: Int
    }

    struct Choice: Identifiable, Equatable {
        let id: String
        let title: String
        let blurb: String
        let symbol: String
    }

    static let roles: [Role] = [
        Role(
            name: "Dev", purpose: "Builds features, opens PRs", symbol: "chevron.left.forwardslash.chevron.right",
            harness: "codex", model: "gpt-5.5", budget: 8_000_000,
            instructions:
                "You implement issues assigned to you. Read the issue and the linked requirement first, work in your worktree, keep the diff focused, and open one PR per issue."
        ),
        Role(
            name: "QA", purpose: "Tests, reviews, gates merges", symbol: "checkmark.shield", harness: "claude",
            model: "sonnet-5", budget: 5_000_000,
            instructions:
                "You verify finished issues against their acceptance criteria. Run the tests, try the edge cases, and block the merge with a clear reproduction when something fails."
        ),
        Role(
            name: "Lead", purpose: "Splits work, reviews code", symbol: "star", harness: "claude", model: "opus-5.5",
            budget: 12_000_000,
            instructions:
                "You split requirements into issues, assign them to the team, and review every PR before QA. Escalate scope or budget questions to the PO."
        ),
        Role(
            name: "PO", purpose: "Turns goals into backlog", symbol: "doc.text", harness: "claude", model: "sonnet-5",
            budget: 6_000_000,
            instructions:
                "You turn requirements into a prioritised backlog with acceptance criteria, plan the sprint with the lead, and ask the requester when something is ambiguous."
        ),
        Role(
            name: "DevOps", purpose: "CI, deploys, runners", symbol: "server.rack", harness: "agy", model: "gemini-3",
            budget: 4_000_000,
            instructions:
                "You keep CI green and the runners healthy. Fix pipeline failures, keep build times down, and never deploy without an approved release."
        ),
        Role(
            name: "Writer", purpose: "Docs, posts, release notes", symbol: "pencil", harness: "claude",
            model: "sonnet-5", budget: 4_000_000,
            instructions:
                "You write docs, posts and release notes in the company voice. Draft, ask for review, and keep claims to what the product actually does."
        ),
        Role(
            name: "Designer", purpose: "Mockups, assets, UI copy", symbol: "paintpalette", harness: "agy",
            model: "gemini-3", budget: 4_000_000,
            instructions:
                "You produce mockups and assets that follow the brand kit. Deliver screen by screen and attach previews to the issue."
        ),
        Role(
            name: "Analyst", purpose: "Data, reports, research", symbol: "chart.bar", harness: "opencode",
            model: "qwen3", budget: 3_000_000,
            instructions:
                "You answer questions with data. State the source and the query, keep notebooks reproducible, and flag low-confidence results."
        ),
    ]

    static let harnesses = ["claude", "codex", "opencode", "agy"]

    static let models: [String: [Model]] = [
        "claude": [
            Model(wire: "opus-5.5", name: "Opus 5.5", blurb: "deepest reasoning", quality: 4, speed: 2, cost: 4),
            Model(wire: "sonnet-5", name: "Sonnet 5", blurb: "the everyday default", quality: 3, speed: 3, cost: 2),
            Model(wire: "haiku-5", name: "Haiku 5", blurb: "fast and cheap", quality: 2, speed: 4, cost: 1),
        ],
        "codex": [
            Model(wire: "gpt-5.5", name: "gpt-5.5", blurb: "strong at code", quality: 4, speed: 3, cost: 3),
            Model(wire: "gpt-5.5-mini", name: "gpt-5.5-mini", blurb: "quick edits", quality: 2, speed: 4, cost: 1),
        ],
        "opencode": [
            Model(wire: "qwen3-coder", name: "qwen3-coder", blurb: "open weights, code", quality: 3, speed: 3, cost: 1),
            Model(wire: "qwen3", name: "qwen3", blurb: "open weights", quality: 2, speed: 3, cost: 1),
        ],
        "agy": [
            Model(wire: "gemini-3", name: "Gemini 3", blurb: "long context", quality: 3, speed: 3, cost: 2),
            Model(
                wire: "gemini-3-flash", name: "Gemini 3 Flash", blurb: "fast and cheap", quality: 2, speed: 4, cost: 1),
        ],
    ]

    static let sandboxes: [Choice] = [
        Choice(
            id: "read-only", title: "Read only", blurb: "Reads code and runs read commands — changes nothing",
            symbol: "eye"),
        Choice(
            id: "workspace-write", title: "Workspace", blurb: "Edits its own worktree · no network without asking",
            symbol: "folder.badge.gearshape"),
        Choice(
            id: "full-access", title: "Full access", blurb: "Network and installs — asks less, risk is higher",
            symbol: "lock.open"),
    ]

    static let efforts: [Choice] = [
        Choice(id: "low", title: "Low", blurb: "Fast, shallow passes", symbol: ""),
        Choice(id: "medium", title: "Medium", blurb: "Balanced — the default", symbol: ""),
        Choice(id: "high", title: "High", blurb: "Thorough, slower, costlier", symbol: ""),
    ]

    static let runnerTags: [(tag: String, title: String)] = [
        ("linux", "Linux"), ("macos", "macOS"), ("docker", "Docker"), ("arm64", "ARM64"),
    ]

    static let guidelines: [(glyph: String, text: String)] = [
        ("⑂", "Open one PR per issue"), ("⛨", "Never push to protected branches"),
        ("＋", "Ask before adding a dependency"), ("✓", "Write or update tests with every change"),
        ("⚑", "Escalate after 3 identical failures"), ("◔", "Stay inside the run's token cap"),
    ]

    static let names = [
        "Onyx", "Wisp", "Cinder", "Moss", "Halo", "Fable", "Rune", "Thistle", "Ember", "Lumen", "Sorrel", "Vale",
    ]

    /// Budget presets, tokens a month.
    static let budgetPresets: [Int64] = [2_500_000, 5_000_000, 8_000_000, 12_000_000, 20_000_000]

    static func role(_ name: String) -> Role? { roles.first { $0.name.lowercased() == name.lowercased() } }

    static func modelName(_ wire: String) -> String {
        models.values.flatMap { $0 }.first { $0.wire == wire }?.name ?? wire
    }
}
