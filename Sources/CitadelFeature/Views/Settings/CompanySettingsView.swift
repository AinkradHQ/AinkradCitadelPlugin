import AinkradAppKit
import SwiftUI

/// Company settings (⚙ next to the switcher), System Settings style (prototype `settings.js`): the company, its
/// sections as tinted icon rows under one gliding highlight, the server at the foot; the section's page beside it.
struct CompanySettingsView: View {
    let store: CitadelStore
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let section = store.model?.limitsPage.section ?? .general
        HStack(spacing: 0) {
            SettingsSidebar(store: store, section: section)
            Group {
                switch (section, store.model) {
                case (.general, _): GeneralSection(store: store)
                case (.limits, let model?): LimitsView(store: store, model: model)
                case (.devices, let model?): DevicesSection(store: store, model: model)
                case (.accounts, let model?): AccountAssignmentSection(store: store, model: model)
                case (.notifications, _): NotificationsSection()
                case (.audit, let model?): AuditLogSection(store: store, model: model)
                case (.skills, let model?): SkillsSection(store: store, model: model)
                default: FirstLoadView()
                }
            }
            .id(section)
            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(y: skin.size.s8)))
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            .offlineDimmed()
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: section)
    }
}

/// The section column (`sx-side`).
private struct SettingsSidebar: View {
    let store: CitadelStore
    let section: CompanySettingsSection
    @Namespace private var glide
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s8) {
            if let company = store.company {
                HStack(spacing: skin.size.s10) {
                    CompanyMark(
                        company: company, size: skin.size.s36, live: false, radius: skin.size.s11, fontKey: "t16")
                    VStack(alignment: .leading, spacing: skin.size.s1) {
                        Text(company.name).citadelFont("t14", weight: "semibold").foregroundStyle(
                            skin.color(skin.text.primary))
                        Text("Company settings").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    }
                }
                .padding(.horizontal, skin.size.s8)
                .padding(.top, skin.size.s6)
                .padding(.bottom, skin.size.s10)
            }
            VStack(spacing: skin.size.s2) {
                ForEach(CompanySettingsSection.allCases, id: \.self) { item in
                    SectionRow(item: item, isOn: item == section, count: count(item), glide: glide) {
                        withAnimation(
                            reduceMotion
                                ? nil
                                : skin.animation(AinkradAnimationToken(curve: "spring", response: 0.35, damping: 0.78))
                        ) { store.model?.limitsPage.section = item }
                    }
                }
            }
            Spacer(minLength: 0)
            ServerPill(host: store.host, api: store.apiMinor)
        }
        .padding(.vertical, skin.size.s14)
        .padding(.horizontal, skin.size.s10)
        .frame(width: skin.size.s240)
        .frame(maxHeight: .infinity)
    }

    private func count(_ item: CompanySettingsSection) -> String? {
        guard let page = store.model?.limitsPage else { return nil }
        switch item {
        case .limits: return page.server.isEmpty ? nil : "\(page.server.count)"
        case .audit:
            guard let log = page.auditLog, !log.isEmpty else { return nil }
            return "\(log.count)\(page.auditNext == nil ? "" : "+")"
        default: return nil
        }
    }
}

/// One section row: its tinted glyph (grows a touch on hover), its title and count; the selected one sits on the
/// gliding highlight.
private struct SectionRow: View {
    let item: CompanySettingsSection
    let isOn: Bool
    let count: String?
    let glide: Namespace.ID
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        AinkradTapArea(action: action) {
            HStack(spacing: skin.size.s10) {
                SectionGlyph(icon: item.icon, tint: item.tint(skin), size: skin.size.s26)
                    .scaleEffect(hovering ? 1.06 : 1)
                Text(item.title).citadelFont("t13", weight: isOn ? "semibold" : nil)
                    .foregroundStyle(skin.color(isOn || hovering ? skin.text.primary : skin.text.muted))
                Spacer(minLength: skin.size.s4)
                if let count {
                    Text(count).citadelFont("t10", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.faint))
                        .padding(.horizontal, skin.size.s6).padding(.vertical, skin.size.s1)
                        .background(
                            skin.color(.palette("foreground", skin.opacity.o06)),
                            in: RoundedRectangle(cornerRadius: skin.size.s6))
                }
            }
            .padding(.horizontal, skin.size.s8)
            .padding(.vertical, skin.size.s6)
            .background {
                if isOn {
                    shape.fill(skin.color(.palette("foreground", skin.opacity.o08)))
                        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o06)), lineWidth: 1))
                        .matchedGeometryEffect(id: "highlight", in: glide)
                } else if hovering {
                    shape.fill(skin.color(.palette("foreground", skin.opacity.o05)))
                }
            }
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// "● citadel.ainkrad.io  api 16" with a pulsing dot.
private struct ServerPill: View {
    let host: String
    let api: Int?
    @State private var pulse = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let green = skin.color(skin.palette.success)
        HStack(spacing: skin.size.s8) {
            Circle().fill(green).frame(width: skin.size.s7, height: skin.size.s7)
                .shadow(color: green, radius: skin.size.s8)
                .opacity(pulse ? skin.opacity.o40 : 1)
            Text(host).citadelFont("t11", weight: "semibold", mono: true).foregroundStyle(skin.color(skin.text.primary))
                .lineLimit(1)
            if let api { Text("api \(api)").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)) }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s10)
        .padding(.vertical, skin.size.s8)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)), in: RoundedRectangle(cornerRadius: skin.size.s10)
        )
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 0.8)).repeatForever()) {
                pulse = true
            }
        }
    }
}
