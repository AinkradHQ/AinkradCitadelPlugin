import AinkradAppKit
import Foundation

/// Fallback chain presets (API minor 18): the company's named chains, who is on which, and the default. Each write
/// is gated on the minor; a refusal opens the failure card with the server's words.
extension CitadelStore {
    var chainPresetsOn: Bool { serverSupports(minor: Self.trancheBMinor) }

    /// Reads the presets (Accounts, the agent drawer, Settings and the hire wizards ask when they open).
    func loadChainPresets() {
        guard chainPresetsOn, let server, let model else { return }
        Task { await reloadChainPresets(model, server: server) }
    }

    func reloadChainPresets(_ model: CompanyModel, server: CitadelServer) async {
        guard chainPresetsOn, let presets = await server.chainPresets(company: model.companyID) else { return }
        model.chainPresets = presets
    }

    private func presetFailed(_ title: String, _ answer: ServerAnswer, _ outcome: String) {
        actionFailure = ActionFailure(title: title, answer: answer, outcome: outcome)
        schedule([.presets, .org])
    }

    /// Creates (`isNew`) or replaces a preset; `done` runs with it once the server took it.
    func saveChainPreset(
        _ preset: ChainPresetInfo, isNew: Bool, done: @escaping @MainActor (ChainPresetInfo) -> Void = { _ in }
    ) {
        guard chainPresetsOn, let server, let model else { return }
        let name = preset.name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !name.isEmpty else { return }
        var preset = preset
        preset.name = name
        Task {
            let result =
                isNew
                ? await server.createChainPreset(company: model.companyID, preset)
                : await server.updateChainPreset(preset)
            switch result {
            case .success(let saved):
                actionFailure = nil
                done(saved)
                toast(
                    AinkradRichToast(
                        title: isNew ? "\(saved.name) created" : "\(saved.name) saved",
                        body: isNew ? "Assign it to agents from its card." : "Every agent on it uses the new chain.",
                        status: .success))
                await reloadChainPresets(model, server: server)
                schedule([.org])
            case .failure(let answer):
                presetFailed(
                    isNew ? "Couldn't create \(name)" : "Couldn't save \(name)", answer,
                    isNew ? "No preset was added." : "The preset is unchanged.")
            }
        }
    }

    /// Makes `preset` the chain agents with none of their own start on.
    func makeDefaultChainPreset(_ preset: ChainPresetInfo) {
        var next = preset
        next.isDefault = true
        saveChainPreset(next, isNew: false)
    }

    /// Delete on the preset's drawer: the agents on it go back to their own chain.
    func deleteChainPreset(_ preset: ChainPresetInfo, done: @escaping @MainActor () -> Void = {}) {
        guard chainPresetsOn, let server, let model else { return }
        Task {
            if let answer = await server.deleteChainPreset(preset.id) {
                presetFailed("Couldn't delete \(preset.name)", answer, "The preset is still there.")
            } else {
                done()
                toast(
                    AinkradRichToast(
                        title: "\(preset.name) deleted", body: "Its agents are back on their own chain.",
                        status: .success))
                await reloadChainPresets(model, server: server)
                schedule([.org])
            }
        }
    }

    /// An agent runs on `preset` from the next run on.
    func useChainPreset(_ preset: ChainPresetInfo, for agent: AgentInfo) {
        guard chainPresetsOn, let server, let model else { return }
        Task {
            switch await server.setAgentChain(agent: agent.id, preset: preset.id) {
            case .success:
                model.agents[agent.id]?.chainPresetID = preset.id
                toast(
                    AinkradRichToast(
                        title: "\(agent.name) uses \(preset.name)", body: "From the next run.", status: .success))
                schedule([.org])
            case .failure(let answer):
                presetFailed("Couldn't change \(agent.name)'s chain", answer, "Its chain is unchanged.")
            }
        }
    }

    /// "Customize for …": the agent leaves its preset for fallbacks of its own (a copy of the preset's, minus its
    /// account pins), or clears them with no `entries`.
    func customizeChain(of agent: AgentInfo, entries: [FallbackEntry]) {
        guard chainPresetsOn, let server, let model else { return }
        Task {
            switch await server.setAgentChain(agent: agent.id, entries: entries) {
            case .success(let chain):
                model.agents[agent.id]?.chainPresetID = chain.preset
                model.accountsPage.agentFallbacks[agent.id] = chain.entries
                if model.accountsPage.chainAgent == agent.id {
                    model.accountsPage.chain = model.accountsPage.chain.filter(\.isOwn) + chain.entries
                }
                toast(
                    AinkradRichToast(
                        title: "\(agent.name) has its own chain", body: "Edit it on the Agents tab.", status: .success))
                schedule([.org])
            case .failure(let answer):
                presetFailed("Couldn't change \(agent.name)'s chain", answer, "Its chain is unchanged.")
            }
        }
    }

    /// "Save as preset": the agent's own chain becomes a named preset, which it then uses.
    func savePresetFromChain(of agent: AgentInfo, entries: [FallbackEntry]) {
        guard chainPresetsOn, let server, let model else { return }
        let draft = ChainPresetInfo(
            id: 0, name: "\(agent.name)'s chain", description: "", colorHex: nil, isDefault: false,
            entries: entries.filter { !$0.isOwn })
        Task {
            switch await server.createChainPreset(company: model.companyID, draft) {
            case .success(let saved):
                _ = await server.setAgentChain(agent: agent.id, preset: saved.id)
                model.agents[agent.id]?.chainPresetID = saved.id
                await reloadChainPresets(model, server: server)
                toast(
                    AinkradRichToast(
                        title: "\(saved.name) saved as a preset", body: "\(agent.name) uses it now.", status: .success))
                schedule([.org])
            case .failure(let answer):
                presetFailed("Couldn't save the preset", answer, "No preset was added.")
            }
        }
    }

    /// Assign to N: the picked agents use `preset`; agents that had it and were left out get a chain of their own
    /// (a copy of it).
    func assign(_ preset: ChainPresetInfo, to picked: Set<Int64>, done: @escaping @MainActor () -> Void = {}) {
        guard chainPresetsOn, let server, let model else { return }
        let left = model.agents(on: preset).filter { !picked.contains($0.id) }
        Task {
            var failed: ServerAnswer?
            for id in picked where model.agents[id]?.chainPresetID != preset.id {
                switch await server.setAgentChain(agent: id, preset: preset.id) {
                case .success: model.agents[id]?.chainPresetID = preset.id
                case .failure(let answer): failed = failed ?? answer
                }
            }
            for agent in left {
                let copy = preset.entries.map { FallbackEntry(harness: $0.harness, model: $0.model) }
                switch await server.setAgentChain(agent: agent.id, entries: copy) {
                case .success(let chain):
                    model.agents[agent.id]?.chainPresetID = chain.preset
                    model.accountsPage.agentFallbacks[agent.id] = chain.entries
                case .failure(let answer): failed = failed ?? answer
                }
            }
            if let failed {
                presetFailed("Couldn't assign \(preset.name)", failed, "Some agents kept their chain.")
            } else {
                done()
                toast(
                    AinkradRichToast(
                        title: "\(preset.name) assigned",
                        body: "\(Wording.count(picked.count, "agent")) use it · from the next run", status: .success))
            }
            schedule([.org])
        }
    }
}
