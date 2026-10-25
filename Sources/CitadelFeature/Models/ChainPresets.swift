import CitadelClient
import Foundation

/// A named chain of (harness, model, account) entries a company's agents share (API minor 18). An agent on a preset
/// uses its entries, after its own model, in place of its own fallbacks.
struct ChainPresetInfo: Identifiable, Equatable, Sendable {
    let id: Int64
    var name: String
    var description: String
    /// `#rrggbb`, or `nil` for the first entry's harness colour.
    var colorHex: String?
    /// The chain agents with no chain of their own use.
    var isDefault: Bool
    var entries: [FallbackEntry]

    /// The first entry's harness: what tints a preset with no colour.
    var harness: String { entries.first?.harness ?? "claude" }
    /// "gpt-5.5 → opus-5.5 → qwen3-coder".
    var detail: String { description.isEmpty ? entries.map(\.model).joined(separator: " → ") : description }
}

extension ChainPresetInfo {
    init(_ preset: Schemas.ChainPresetOut) {
        self.init(
            id: preset.id, name: preset.name, description: preset.description, colorHex: preset.color,
            isDefault: preset.isDefault, entries: preset.entries.map(FallbackEntry.init))
    }

    /// What `POST /companies/{id}/chain-presets` and `PUT /chain-presets/{id}` take.
    var body: Schemas.ChainPresetBody {
        Schemas.ChainPresetBody(
            color: colorHex, description: description, entries: entries.map(\.entryBody), isDefault: isDefault,
            name: name)
    }
}

extension FallbackEntry {
    init(_ entry: Schemas.ChainEntryBody) {
        self.init(harness: entry.harness.word, model: entry.model, accountID: entry.accountId)
    }

    var entryBody: Schemas.ChainEntryBody {
        Schemas.ChainEntryBody(
            accountId: accountID, harness: .init(value1: .init(rawValue: harness), value2: harness), model: model)
    }
}

extension CompanyModel {
    func chainPreset(_ id: Int64?) -> ChainPresetInfo? { id.flatMap { id in chainPresets.first { $0.id == id } } }
    var defaultChainPreset: ChainPresetInfo? { chainPresets.first(where: \.isDefault) }

    /// The preset an agent runs on: the one it was given, else the company's default while it has no fallbacks of
    /// its own (`fallbacks` is its stored chain, `nil` while unread); `nil` for a custom chain.
    func chainPreset(of agent: AgentInfo, fallbacks: [FallbackEntry]?) -> ChainPresetInfo? {
        if let given = chainPreset(agent.chainPresetID) { return given }
        return (fallbacks ?? []).isEmpty ? defaultChainPreset : nil
    }

    /// The agents set to a preset.
    func agents(on preset: ChainPresetInfo) -> [AgentInfo] {
        agents.values.filter { $0.chainPresetID == preset.id && !$0.isHirePending }.sorted { $0.name < $1.name }
    }
}
