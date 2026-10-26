import AinkradAppKit
import Foundation

/// What the New company wizard has collected so far (prototype `company.js` N and N.ceo).
struct NewCompanyDraft: Equatable {
    static let steps: [(group: String, title: String)] = [
        ("Company", "Identity"), ("CEO", "Profile"), ("CEO", "Instructions"), ("CEO", "Model & budget"),
        ("CEO", "Look"), ("Setup", "Resources"), ("Setup", "Review"),
    ]
    /// The prototype's eight company colours, sent to the server as `#rrggbb`.
    static let swatches = ["2563eb", "10b981", "a855f7", "f59e0b", "ef4444", "0ea5e9", "ec4899", "14b8a6"].map {
        "#" + $0
    }
    static let industries: [(id: String, title: String, symbol: String)] = [
        ("software", "Software", "chevron.left.forwardslash.chevron.right"), ("marketing", "Marketing", "megaphone"),
        ("research", "Research", "magnifyingglass"), ("agency", "Agency", "briefcase"),
        ("ops", "Operations", "gearshape.2"),
    ]
    static let ceoInstructions =
        "You run this company for its owner. Turn each requirement into a plan of epics and issues, propose the hires the plan needs, and keep work inside the company budget. Never start work before the owner approves the plan; summarise progress daily and escalate anything blocked."
    static let ceoNames = ["Atlas"] + HireCatalog.names
    static let tokensPerStep: Int64 = 10_000_000

    var step = 0
    var name = ""
    var kind = "client"
    var industries: Set<String> = ["software"]
    var description = ""
    var website = ""
    var swatch = 1
    var logo: Data?
    /// `image/png`, `image/jpeg` or `image/webp`: what the server takes.
    var logoType: String?
    /// The company's monthly budget in tokens — the server's budgets are tokens, never dollars.
    var budgetTokens: Int64 = 100_000_000
    /// The `$ / tokens` toggle: on, the company budget also carries a dollar cap (`budgetDollars`).
    var budgetInDollars = false
    var budgetDollars: Int64 = 1_000
    var accounts: Set<Int64> = []
    var tags: Set<String> = ["linux"]

    var ceoName = "Atlas"
    var ceoDescription = "Runs the company: plans the work, staffs it and reports progress."
    var sandbox = "read-only"
    var ceoTags: Set<String> = ["linux"]
    var instructions = NewCompanyDraft.ceoInstructions
    var guidelines = HireCatalog.guidelines.prefix(5).map(\.text)
    var allGuidelines = HireCatalog.guidelines.map(\.text)
    var harness = "claude"
    var model = HireCatalog.models["claude"]?.first?.wire ?? ""
    var effort = "high"
    /// A chain preset of the company the wizard was opened in, copied into the new one for its CEO (API minor 18).
    var chainTemplate: Int64?
    var ceoBudget = Fmt.tokens(40_000_000)
    var warn = "80"
    var cap = "200k"
    var palette = AinkradFigurePalette.all[3 % AinkradFigurePalette.all.count].id

    var hasName: Bool { !name.trimmingCharacters(in: .whitespaces).isEmpty }
    var cleanName: String { name.trimmingCharacters(in: .whitespaces) }
    var colour: String { Self.swatches[swatch] }
    /// The dollar cap sent as `usdCapMicros` (millionths); `nil` while the toggle is on tokens.
    var usdCapMicros: Int64? { budgetInDollars ? max(0, budgetDollars) * 1_000_000 : nil }
    /// The CEO's share of the company budget, in percent (prototype `Share of company`).
    var ceoShare: Int {
        let ceo = min(budgetTokens, TokenAmount.parse(ceoBudget) ?? 0)
        return Int((Double(ceo) / Double(max(budgetTokens, 1)) * 100).rounded())
    }
    var modelName: String { HireCatalog.modelName(model) }
    /// "Software · Marketing", or "Software +2" past two.
    var industryLine: String {
        let titles = Self.industries.filter { industries.contains($0.id) }.map(\.title)
        return titles.count > 2 ? "\(titles[0]) +\(titles.count - 1)" : titles.joined(separator: " · ")
    }

    /// The figure's pose in the preview follows the step: idle, thinking (instructions), working (model).
    var figureState: AinkradFigureState { [.idle, .idle, .thinking, .working][min(max(step, 0), 3)] }

    /// The wire body: the identity fields only from API minor 17.
    func proposal(extended: Bool) -> AgentDraft {
        var draft = AgentDraft()
        draft.name = ceoName.trimmingCharacters(in: .whitespaces)
        draft.role = "CEO"
        draft.orgRole = "ceo"
        draft.harness = harness
        draft.model = model
        draft.runnerTags = ceoTags.sorted().joined(separator: " ")
        let about = ceoDescription.trimmingCharacters(in: .whitespacesAndNewlines)
        draft.justification = about.isEmpty ? "Runs \(cleanName) for its owner." : about
        if extended {
            draft.description = about
            draft.effort = effort
            draft.sandbox = sandbox
            draft.instructions = instructions
            draft.guidelines = guidelines
            draft.paletteID = palette
        }
        return draft
    }
}

/// The wizard's state in the store, so ⌘K, the switcher and the sweep open it the same way: the draft, the
/// pool and runners it picks from, and whether Create is in flight.
struct NewCompanySession: Equatable {
    var draft = NewCompanyDraft()
    var pool: [PoolAccount] = []
    var runners: [RunnerInfo] = []
    var isCreating = false
}
