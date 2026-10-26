import AinkradAppKit
import CitadelClient
import SwiftUI

/// "New company" (prototype `company.js` `ACT.newCompany`): a 1060 pt sheet — the form on the left (title, grouped
/// step bar, scrolling body, pinned footer) and a 300 pt live preview on the right. Seven steps: Identity · CEO
/// profile, instructions, model & budget, look · Resources · Review. Create is not atomic; see
/// `CitadelStore.createCompany`.
struct NewCompanyWizard: View {
    @Bindable var store: CitadelStore
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var draft: Binding<NewCompanyDraft> { $store.newCompany.draft }
    private var last: Int { NewCompanyDraft.steps.count - 1 }

    var body: some View {
        let step = store.newCompany.draft.step
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                top
                ScrollView {
                    NewCompanyStepPane(store: store, draft: draft)
                        .id(step)
                        .ainkradRiseIn()
                        .padding(.horizontal, skin.size.s26)
                        .padding(.top, skin.size.s8)
                        .padding(.bottom, skin.size.s18)
                }
                .scrollIndicators(.never)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: step)
                footer
            }
            .frame(maxWidth: .infinity)
            NewCompanyPreview(draft: store.newCompany.draft, fallback: store.newCompanyFallbackName)
                .frame(width: skin.size.s300)
        }
        .frame(height: skin.size.s640 + skin.size.s80)
        // The panel pads its content; the sheet is flush to its edges.
        .padding(.horizontal, -skin.size.s24)
        .padding(.vertical, -skin.size.s22)
        .onAppear { if store.newCompany.pool.isEmpty { store.loadNewCompanyChoices() } }
    }

    private var top: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("New company").citadelFont("t20", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
            NewCompanyStepBar(current: store.newCompany.draft.step, unlocked: store.newCompany.draft.hasName) {
                draft.wrappedValue.step = $0
            }
        }
        .padding(.horizontal, skin.size.s26)
        .padding(.top, skin.size.s22)
        .padding(.bottom, skin.size.s10)
    }

    private var footer: some View {
        let current = store.newCompany.draft
        let isLast = current.step == last
        return HStack(spacing: skin.size.s12) {
            AinkradDockButton(current.step == 0 ? "Cancel" : "Back") {
                if current.step == 0 { store.isCreatingCompany = false } else { draft.wrappedValue.step -= 1 }
            }
            Text("Step \(current.step + 1) of \(NewCompanyDraft.steps.count)").citadelFont("t11_5")
                .foregroundStyle(skin.color(skin.text.faint))
            Spacer(minLength: 0)
            AinkradDockButton(
                store.newCompany.isCreating
                    ? "Creating…"
                    : isLast ? "Create company" : "Next · \(NewCompanyDraft.steps[current.step + 1].title)",
                tone: .primary, isEnabled: current.hasName && !store.newCompany.isCreating
            ) { next() }
        }
        .padding(.horizontal, skin.size.s26)
        .padding(.vertical, skin.size.s14)
    }

    private func next() {
        if store.newCompany.draft.step == last { store.createCompany() } else { draft.wrappedValue.step += 1 }
    }
}
