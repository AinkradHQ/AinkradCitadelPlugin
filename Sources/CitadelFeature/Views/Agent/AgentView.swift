import AinkradAppKit
import SwiftUI

/// Screen 04 (prototype `agent.js`): one agent as a parallax stage (figure, identity, three ring stats, the dock),
/// a bento board (Now, budget burn, success, when it works, chain, skills), its recent runs as cards, and a drawer
/// with Instructions / Skills / Settings.
struct AgentView: View {
    let store: CitadelStore
    let model: CompanyModel
    let agentID: Int64
    @State private var width: CGFloat = 0
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        if let agent = model.agents[agentID] {
            let page = model.orgPage
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s14) {
                    AgentStage(store: store, model: model, agent: agent)
                    if agent.isPaused { pausedBar(agent) }
                    AgentBento(
                        store: store, model: model, agent: agent,
                        wide: width == 0 || width >= skin.size.s860 + skin.size.s40)
                    AgentRunCards(store: store, model: model, agent: agent)
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.vertical, skin.size.s14)
            }
            .onGeometryChange(for: CGFloat.self) {
                $0.size.width
            } action: {
                width = $0
            }
            .overlay {
                if let drawer = page.drawer {
                    AgentDrawer(store: store, model: model, agent: agent, drawer: drawer)
                        .transition(.opacity)
                }
            }
            .animation(skin.animation(skin.motion.hover), value: page.drawer)
            .offlineDimmed()
            .orgSheets(store, model)
            .task(id: agentID) { store.loadAgentExtras(agentID) }
        } else {
            VStack(spacing: skin.size.s14) {
                AinkradEmptyState(
                    icon: "diamond", title: "No agent called “\(agentID)”", message: "It may have been terminated.")
                AinkradButton(title: "Back to Org", style: .secondary) { store.open(nil) }.fixedSize()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private func pausedBar(_ agent: AgentInfo) -> some View {
        HStack(spacing: skin.size.s10) {
            Text("⏸").foregroundStyle(status.warning)
            Text("Paused by you · new wakes queue until you resume")
            Spacer()
            AinkradButton(title: "Resume", style: .secondary) { store.resume(agent) }.compact().fixedSize()
        }
        .citadelFont("t12")
        .padding(.horizontal, skin.size.s12).padding(.vertical, skin.size.s8)
        .background(status.warning.opacity(skin.opacity.o10), in: RoundedRectangle(cornerRadius: skin.size.s8))
    }
}

extension CompanyModel {
    /// `Engineering › Citadel Core`.
    func place(of agent: Int64) -> String? {
        team(of: agent).map { "\($0.0.name) › \($0.1.name)" }
    }
}
