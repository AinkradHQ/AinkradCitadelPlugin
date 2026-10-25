import AinkradAppKit
import SwiftUI

/// Accounts › Add account (`acctAdd`): provider cards, kind, label, where the credential lives (a reference — never
/// the secret), config dir, the companies it serves, and a live preview. Health checks on save need the server's
/// runner probe, so the preview says the runners report it on their next probe.
struct AddAccountSheet: View {
    let store: CitadelStore
    let page: AccountsPage
    @Binding var isPresented: Bool
    @State private var draft = NewAccountDraft(label: "claude-max-4")
    @State private var companies: Set<Int64> = []
    @Environment(\.ainkradSkin) private var skin

    private static let providers: [(String, String, String)] = [
        ("claude", "Claude", "Max / Pro login or API key"), ("codex", "Codex", "ChatGPT Pro / Team login"),
        ("opencode", "OpenCode", "any provider key"), ("agy", "agy", "Gemini login"),
    ]

    var body: some View {
        OpsDrawerPanel(crumb: ["Accounts", "Add account"], close: { isPresented = false }) {
            OpsHint(
                "A login or key you own. Credentials stay on the runners as a config dir — Citadel only stores a reference."
            )
            OpsSection(title: "Provider") {
                OpsChoiceGrid(
                    cards: Self.providers.map { harness, name, detail in
                        OpsChoice(
                            id: harness, title: name, detail: detail,
                            leading: AnyView(SolidHarnessTag(harness: harness, size: skin.size.s40)),
                            tint: AgentLook.harness(harness)?.color)
                    }, columns: 4, centered: true, isOn: { $0 == draft.harness }
                ) { harness in
                    if let old = Self.providers.map(\.0).first(where: { draft.label.hasPrefix($0) }) {
                        draft.label = harness + draft.label.dropFirst(old.count)
                    }
                    draft.harness = harness
                }
            }
            OpsSection(title: "Kind") {
                OpsChoiceGrid(
                    cards: [
                        OpsChoice(
                            id: "subscription", title: "Subscription login", detail: "usage windows, counted in tokens",
                            systemImage: "square.stack.3d.up"),
                        OpsChoice(
                            id: "metered", title: "API key", detail: "billed per token, counted in $",
                            systemImage: "key"),
                    ], columns: 2, isOn: { $0 == draft.billing }, pick: { draft.billing = $0 })
            }
            OpsSection(title: "Label", hint: "config dir ~/.citadel/acct/<label>") {
                AinkradTextField(text: $draft.label, placeholder: "claude-max-4").monospaced()
            }
            OpsSection(title: "Credential", hint: "where it lives on the runner — never the secret") {
                AinkradSegmentedPicker(items: ["file", "env"], selection: $draft.credentialKind) {
                    $0 == "file" ? "File or vault path" : "Environment variable"
                }
                .fixedSize()
                AinkradTextField(
                    text: $draft.credential,
                    placeholder: draft.credentialKind == "file" ? "~/.citadel/keys/anthropic" : "ANTHROPIC_API_KEY"
                )
                .monospaced()
                AinkradTextField(text: $draft.configDir, placeholder: "config dir — empty: the server picks one")
                    .monospaced()
            }
            OpsSection(title: "Companies") {
                AinkradFlowLayout(spacing: skin.size.s8, lineSpacing: skin.size.s8) {
                    ForEach(Array(store.companies.enumerated()), id: \.element.id) { index, company in
                        companyChip(company.id, name: company.name, index: index)
                    }
                }
            }
            OpsSection(title: "Preview") {
                OpsDrawerHero(
                    tint: AgentLook.harness(draft.harness)?.color ?? skin.color(skin.palette.accentPrimary),
                    title: draft.label.isEmpty ? "—" : draft.label,
                    subtitle: "\(AgentLook.harnessName(draft.harness)) · "
                        + (draft.billing == "subscription" ? "subscription" : "API key")
                        + " · \(Wording.count(companies.count, "company", plural: "companies"))"
                ) {
                    SolidHarnessTag(harness: draft.harness, size: skin.size.s44)
                } trailing: {
                    StatePill(
                        text: "runners report it on their next probe", tint: skin.color(skin.palette.accentPrimary),
                        dot: true)
                }
            }
            if let failure = page.addFailure {
                RefusalLine(failure: failure)
            } else if let problem = draft.label.isEmpty ? nil : draft.problem {
                OpsHint(problem)
            }
        } footer: {
            Spacer()
            AinkradDockButton("Cancel") {
                page.addFailure = nil
                isPresented = false
            }
            AinkradDockButton("Add account", tone: .primary, isEnabled: draft.problem == nil) {
                store.addAccount(draft, companies: companies.sorted()) { isPresented = false }
            }
        }
        .onAppear { if let id = store.model?.companyID { companies = [id] } }
    }

    private func companyChip(_ id: Int64, name: String, index: Int) -> some View {
        let isOn = companies.contains(id)
        let palette: [Color] = [
            skin.color(skin.palette.accentPrimary), skin.color(skin.palette.success),
            skin.color(skin.palette.accentViolet), skin.color(skin.palette.accentSecondary),
        ]
        let tint = palette[index % palette.count]
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        return AinkradTapArea(action: { if isOn { companies.remove(id) } else { companies.insert(id) } }) {
            HStack(spacing: skin.size.s8) {
                Text(String(name.prefix(1))).citadelFont("t11", weight: "bold")
                    .foregroundStyle(skin.color(.palette("foreground", 1)))
                    .frame(width: skin.size.s22, height: skin.size.s22)
                    .background(tint, in: RoundedRectangle(cornerRadius: skin.size.s7, style: .continuous))
                    .opacity(isOn ? 1 : skin.opacity.o50)
                Text(name).citadelFont("t12")
                    .foregroundStyle(isOn ? skin.color(skin.text.primary) : skin.color(skin.text.faint))
            }
            .padding(.leading, skin.size.s6)
            .padding(.trailing, skin.size.s12)
            .frame(height: skin.size.s34)
            .background(
                shape.fill(isOn ? tint.opacity(skin.opacity.o12) : skin.color(.palette("black", skin.opacity.o18)))
            )
            .overlay(
                shape.strokeBorder(
                    isOn ? tint.opacity(skin.opacity.o55) : skin.color(.palette("foreground", skin.opacity.o07)),
                    lineWidth: 1))
        }
    }
}
