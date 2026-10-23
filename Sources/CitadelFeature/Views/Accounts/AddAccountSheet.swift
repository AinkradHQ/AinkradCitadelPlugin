import AinkradAppKit
import SwiftUI

/// "+ Add account": a provider login for the pool. Its credential is only a reference — an environment variable's
/// name or a path on the runner — and this sheet never takes or shows the secret itself.
struct AddAccountSheet: View {
    let store: CitadelStore
    let page: AccountsPage
    @Binding var isPresented: Bool
    @State private var draft = NewAccountDraft()
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Add account").citadelFont("t15", weight: "semibold")
            AinkradFormRow(title: "Name") { AinkradTextField(text: $draft.label, placeholder: "claude-personal") }
            AinkradFormRow(title: "Harness") {
                AinkradSegmentedPicker(items: NewAccountDraft.harnesses, selection: $draft.harness) {
                    AgentLook.harnessName($0)
                }
                .fixedSize()
            }
            AinkradFormRow(title: "Billing", help: "A subscription counts tokens; an API key counts dollars.") {
                AinkradSegmentedPicker(items: ["subscription", "metered"], selection: $draft.billing) {
                    $0 == "subscription" ? "Subscription" : "API key · priced"
                }
                .fixedSize()
            }
            AinkradFormRow(
                title: "Credential", help: "Where the login or key lives on the runner — never the secret itself."
            ) {
                VStack(alignment: .leading, spacing: skin.size.s6) {
                    AinkradSegmentedPicker(items: ["file", "env"], selection: $draft.credentialKind) {
                        $0 == "file" ? "File or vault path" : "Environment variable"
                    }
                    .fixedSize()
                    AinkradTextField(
                        text: $draft.credential,
                        placeholder: draft.credentialKind == "file" ? "~/.citadel/keys/anthropic" : "ANTHROPIC_API_KEY")
                }
            }
            AinkradFormRow(title: "Config directory", help: "Left empty, the server picks one per account.") {
                AinkradTextField(text: $draft.configDir, placeholder: "~/.citadel/acct/claude-personal")
            }
            if let failure = page.addFailure {
                RefusalLine(failure: failure)
            } else if let problem = draft.label.isEmpty ? nil : draft.problem {
                Text(problem).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            }
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) {
                    page.addFailure = nil
                    isPresented = false
                }
                .fixedSize()
                AinkradButton(title: "Add") { store.addAccount(draft) { isPresented = false } }
                    .fixedSize()
                    .disabled(draft.problem != nil)
            }
        }
        .padding(skin.size.s20)
        .frame(width: skin.size.s480)
    }
}
