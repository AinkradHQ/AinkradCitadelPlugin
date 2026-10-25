import CitadelClient
import Foundation

/// Chain presets and an agent's chain (API minor 18). The screens gate on the minor, so an older server's 404 is
/// never asked for.
extension CitadelServer {
    func chainPresets(company: Int64) async -> [ChainPresetInfo]? {
        await read("listChainPresets") {
            guard case .ok(let ok) = try await client.listChainPresets(path: .init(id: company)) else { return nil }
            return try ok.body.json.map(ChainPresetInfo.init)
        }
    }

    /// Creates the preset (`409` for a name the company has, `400` for a pin outside the pool).
    func createChainPreset(company: Int64, _ preset: ChainPresetInfo) async -> Result<ChainPresetInfo, ServerAnswer> {
        await attempt({ try await client.createChainPreset(path: .init(id: company), body: .json(preset.body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return ChainPresetInfo(try ok.body.json)
        }
    }

    /// Replaces all of the preset; `isDefault` moves the company's default to it.
    func updateChainPreset(_ preset: ChainPresetInfo) async -> Result<ChainPresetInfo, ServerAnswer> {
        await attempt({ try await client.updateChainPreset(path: .init(id: preset.id), body: .json(preset.body)) }) {
            guard case .ok(let ok) = $0 else { return nil }
            return ChainPresetInfo(try ok.body.json)
        }
    }

    /// The agents on it go back to their own chain.
    func deleteChainPreset(_ id: Int64) async -> ServerAnswer? {
        await act { try await client.deleteChainPreset(path: .init(id: id)) }
    }

    /// Gives the agent a preset (`preset`), or fallbacks of its own (`entries`, no account pins; empty clears them).
    /// The chain it has after, past its own entry.
    func setAgentChain(agent: Int64, preset: Int64? = nil, entries: [FallbackEntry]? = nil) async -> Result<
        (preset: Int64?, entries: [FallbackEntry]), ServerAnswer
    > {
        await attempt({
            try await client.setAgentChain(
                path: .init(id: agent),
                body: .json(.init(entries: entries?.filter { !$0.isOwn }.map(\.entryBody), presetId: preset)))
        }) {
            guard case .ok(let ok) = $0 else { return nil }
            let chain = try ok.body.json
            return (chain.presetId, chain.entries.map(FallbackEntry.init))
        }
    }
}
