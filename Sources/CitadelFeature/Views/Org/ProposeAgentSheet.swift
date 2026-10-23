import AinkradAppKit
import SwiftUI

/// "Propose an agent…": who, what it runs on and why — a hire approval, never a running agent until approved.
struct ProposeAgentSheet: View {
    let store: CitadelStore
    let model: CompanyModel
    @Binding var isPresented: Bool
    @State private var draft = AgentDraft()
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let manager = draft.reportsTo.flatMap { model.agent($0) }
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Propose an agent").citadelFont("t15", weight: "semibold")
            Text("It joins as a hire you approve in the inbox; nothing runs before that.")
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            AinkradFormRow(title: "Name") { AinkradTextField(text: $draft.name, placeholder: "Wren") }
            AinkradFormRow(title: "Role") { AinkradTextField(text: $draft.role, placeholder: "QA") }
            AinkradFormRow(title: "Harness") {
                AinkradSegmentedPicker(items: AgentDraft.harnesses, selection: $draft.harness) {
                    AgentLook.harnessName($0)
                }
                .fixedSize()
            }
            AinkradFormRow(title: "Model") { AinkradTextField(text: $draft.model, placeholder: "claude-sonnet-4-5") }
            AinkradFormRow(title: "Reports to") {
                AinkradMenuButton(
                    items: [AinkradMenuItem(title: "Nobody", systemName: nil) { draft.reportsTo = nil }]
                        + model.agents.values.sorted { $0.name < $1.name }.map { agent in
                            AinkradMenuItem(title: "\(agent.name) · \(agent.role)", systemName: nil) {
                                draft.reportsTo = agent.id
                            }
                        }
                ) { Text(manager.map { "\($0.name) · \($0.role)" } ?? "Nobody") }
            }
            AinkradFormRow(title: "Runner tags", help: "Space-separated; empty runs anywhere.") {
                AinkradTextField(text: $draft.runnerTags, placeholder: "macos xcode-27").monospaced()
            }
            AinkradFormRow(title: "Why") {
                AinkradTextField(text: $draft.justification, placeholder: "Reviews every PR before merge")
            }
            if !draft.name.isEmpty, let problem = draft.problem {
                Text(problem).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            }
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { isPresented = false }.fixedSize()
                AinkradButton(title: "Propose") { store.proposeAgent(draft) { isPresented = false } }
                    .fixedSize()
                    .disabled(draft.problem != nil)
            }
        }
    }
}
