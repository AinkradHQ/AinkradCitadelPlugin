import AinkradAppKit
import SwiftUI

/// Company settings (⚙ next to the switcher): its sections beside the selected one — Limits (screen 16) among them.
struct CompanySettingsView: View {
    let store: CitadelStore
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let section = store.model?.limitsPage.section ?? .general
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PaneTitle(title: "Company settings", crumb: nil)
                AinkradNavList(
                    items: CompanySettingsSection.allCases,
                    selection: Binding(get: { section }, set: { store.model?.limitsPage.section = $0 }),
                    icon: { _ in nil }, label: \.title
                )
                .counts { item in
                    guard item == .limits, let count = store.model?.limitsPage.server.count, count > 0 else {
                        return nil
                    }
                    return AinkradNavCount("\(count)")
                }
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, skin.size.s8)
                Spacer(minLength: 0)
            }
            .frame(width: skin.size.s200)
            .background(theme.surface.opacity(skin.opacity.o20))
            Group {
                switch (section, store.model) {
                case (.limits, let model?): LimitsView(store: store, model: model)
                case (.general, _):
                    VStack(alignment: .leading, spacing: 0) {
                        PaneTitle(title: "General", crumb: nil)
                        SettingsView(store: store)
                        Spacer(minLength: 0)
                    }
                case (.devices, let model?): DevicesSection(store: store, page: model.limitsPage)
                case (.accounts, let model?): AccountAssignmentSection(store: store, model: model)
                case (.audit, let model?): AuditLogSection(store: store, model: model)
                case (.skills, let model?): SkillsSection(store: store, model: model)
                default: FirstLoadView()
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
    }
}
