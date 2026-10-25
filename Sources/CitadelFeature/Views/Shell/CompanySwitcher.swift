import AinkradAppKit
import CitadelClient
import SwiftUI

/// The company card at the top of the sidebar (prototype `company.js`): the company's colour as a glowing glass
/// card, its mark with a live dot, "4 working · 8 need you", and the menu of companies on this server.
struct CompanySwitcher: View {
    @Bindable var store: CitadelStore
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        if let company = store.company {
            card(company)
                .ainkradPopover(isPresented: $store.isSwitchingCompany) { menu(current: company) }
        }
    }

    private func card(_ company: Components.Schemas.Company) -> some View {
        let tint = CompanyLook.color(company, skin: skin)
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        return AinkradTapArea {
            store.isSwitchingCompany.toggle()
        } label: {
            HStack(spacing: skin.size.s10) {
                CompanyMark(
                    company: company, size: skin.size.s34, live: (store.model?.busyAgents ?? 0) > 0,
                    logo: store.logos.images[company.id])
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    HStack(spacing: skin.size.s6) {
                        Text(company.name).citadelFont("t13", weight: "bold")
                            .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                        KindChip(company: company)
                    }
                    statusLine
                }
                .layoutPriority(1)
                Spacer(minLength: 0)
                Image(systemName: "chevron.up.chevron.down").citadelFont("t10", weight: "semibold")
                    .foregroundStyle(
                        skin.color(hovering || store.isSwitchingCompany ? skin.text.primary : skin.text.muted)
                    )
                    .frame(width: skin.size.s22, height: skin.size.s26)
                    .background(
                        RoundedRectangle(cornerRadius: skin.size.s7, style: .continuous)
                            .fill(
                                skin.color(
                                    .palette(
                                        "foreground",
                                        hovering || store.isSwitchingCompany ? skin.opacity.o10 : skin.opacity.o05))))
            }
            .padding(skin.size.s8)
            .background {
                ZStack(alignment: .topLeading) {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(skin.opacity.o16), skin.color(.palette("foreground", skin.opacity.o03)),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                    RadialGradient(
                        colors: [tint.opacity(skin.opacity.o25), .clear], center: .topLeading, startRadius: 0,
                        endRadius: skin.size.s120
                    )
                    .offset(
                        x: hovering && !reduceMotion ? skin.size.s14 : 0,
                        y: hovering && !reduceMotion ? skin.size.s8 : 0
                    )
                    .clipShape(shape)
                }
            }
            .overlay(
                shape.strokeBorder(
                    tint.opacity(
                        store.isSwitchingCompany ? skin.opacity.o60 : hovering ? skin.opacity.o50 : skin.opacity.o28),
                    lineWidth: 1)
            )
            .shadow(color: skin.color(.palette("black", skin.opacity.o25)), radius: skin.size.s10, y: skin.size.s6)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .offset(y: hovering && !reduceMotion ? -skin.size.s1 : 0)
        .animation(skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.4)), value: hovering)
        .onHover { hovering = $0 }
        .help("Switch company")
    }

    @ViewBuilder private var statusLine: some View {
        if let model = store.model {
            if model.agents.isEmpty {
                Text("no agents yet").citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
            } else if model.busyAgents == 0 && model.needsYouCount == 0 {
                Text("all clear").citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
            } else {
                HStack(spacing: skin.size.s6) {
                    if model.busyAgents > 0 {
                        Text("\(model.busyAgents) working").citadelFont("t10_5", weight: "semibold")
                            .foregroundStyle(skin.color(skin.palette.accentSecondary))
                    }
                    if model.needsYouCount > 0 {
                        Text("\(model.needsYouCount) need you").citadelFont("t10_5", weight: "semibold")
                            .foregroundStyle(skin.color(skin.palette.warning))
                    }
                }
                .fixedSize()
            }
        } else {
            Text("loading…").citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
        }
    }

    private func menu(current: Components.Schemas.Company) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s2) {
            Text("Companies on \(store.host)").citadelFont("t10_5", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.faint))
                .padding(.horizontal, skin.size.s10)
                .padding(.vertical, skin.size.s6)
            ForEach(Array(store.companies.enumerated()), id: \.element.id) { index, company in
                MenuRow(
                    leading: AnyView(
                        CompanyMark(
                            company: company, size: skin.size.s32, live: false, fontKey: "t14",
                            logo: store.logos.images[company.id])),
                    title: company.name, chip: AnyView(KindChip(company: company)),
                    detail: company.id == current.id ? currentDetail : "Switch to see its work",
                    badge: company.id == current.id
                        ? store.model.map(\.needsYouCount).flatMap { $0 > 0 ? "\($0)" : nil }
                        : nil,
                    hint: index < 9 ? "⌘\(index + 1)" : nil, checked: company.id == current.id
                ) {
                    store.isSwitchingCompany = false
                    if company.id != current.id { store.select(company: company.id) }
                }
            }
            Spacer().frame(height: skin.size.s6)
            MenuRow(
                leading: AnyView(NewCompanyTile(size: skin.size.s32)), title: "New company",
                detail: "Name it, hire its CEO, set its budget"
            ) { store.openNewCompany() }
            MenuRow(
                leading: AnyView(GlyphTile(icon: "gearshape", size: skin.size.s32)), title: "Company settings",
                detail: current.name
            ) {
                store.isSwitchingCompany = false
                store.isShowingSettings = true
            }
        }
        .padding(skin.size.s5)
        .frame(minWidth: skin.size.s300)
    }

    private var currentDetail: String {
        guard let model = store.model else { return "loading…" }
        return "\(model.agents.count) agents · \(model.projects.count) projects"
    }
}

/// A company's mark: its logo when it has one, else its initial on its colour, with the live dot.
struct CompanyMark: View {
    let company: Components.Schemas.Company
    let size: CGFloat
    var live: Bool
    var radius: CGFloat?
    var fontKey = "t15"
    /// The uploaded logo, read from `store.logos`.
    var logo: NSImage?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = CompanyLook.color(company, skin: skin)
        let shape = RoundedRectangle(cornerRadius: radius ?? size * 0.3, style: .continuous)
        Group {
            if let logo {
                Image(nsImage: logo).resizable().scaledToFill().frame(width: size, height: size).clipShape(shape)
            } else {
                Text(String(company.name.prefix(1)).uppercased())
                    .citadelFont(fontKey, weight: "heavy")
                    .foregroundStyle(skin.color(.palette("foreground", 1)))
                    .frame(width: size, height: size)
                    .background(
                        LinearGradient(
                            colors: [tint, skin.color(skin.palette.accentViolet).opacity(skin.opacity.o80)],
                            startPoint: .topLeading, endPoint: .bottomTrailing),
                        in: shape)
            }
        }
        .shadow(color: tint.opacity(skin.opacity.o35), radius: size * 0.2, y: size * 0.08)
        .overlay(alignment: .bottomTrailing) {
            if live {
                LiveDot(size: skin.size.s10).offset(x: skin.size.s3, y: skin.size.s3)
            }
        }
    }
}

/// The green "someone is working" dot with its ping.
struct LiveDot: View {
    let size: CGFloat
    @State private var ping = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let green = skin.color(skin.palette.success)
        Circle().fill(green)
            .frame(width: size, height: size)
            .background(Circle().fill(green).scaleEffect(ping ? 2.4 : 1).opacity(ping ? 0 : skin.opacity.o60))
            .overlay(Circle().strokeBorder(skin.color(.palette("background", 1)), lineWidth: size * 0.25))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 2)).repeatForever(
                        autoreverses: false)
                ) {
                    ping = true
                }
            }
    }
}

/// OWN / CLIENT.
struct KindChip: View {
    let company: Components.Schemas.Company
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let client = company.kind.value1 == .client
        let tint = skin.color(client ? skin.palette.success : skin.palette.accentPrimary)
        Text(client ? "CLIENT" : "OWN").citadelFont("t8_5", weight: "bold").tracking(skin.size.s1 * 0.8)
            .foregroundStyle(tint.opacity(skin.opacity.o90))
            .padding(.horizontal, skin.size.s5)
            .padding(.vertical, skin.size.s1)
            .background(tint.opacity(skin.opacity.o20), in: RoundedRectangle(cornerRadius: skin.size.s5))
    }
}

/// A tinted glyph tile (menu rows, settings sections).
struct GlyphTile: View {
    let icon: String
    let size: CGFloat
    var tint: Color?
    var fontKey = "t13"
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Image(systemName: icon).citadelFont(fontKey, weight: "medium")
            .foregroundStyle(tint ?? skin.color(skin.text.muted))
            .frame(width: size, height: size)
            .background(
                (tint ?? skin.color(skin.text.primary)).opacity(skin.opacity.o08),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// A rich menu row: leading tile, title (+ chip), a faint detail, an amber badge, a shortcut hint, a check.
struct MenuRow: View {
    let leading: AnyView
    let title: String
    var chip: AnyView?
    var detail: String?
    var badge: String?
    var hint: String?
    var checked = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(action: action) {
            HStack(spacing: skin.size.s9) {
                leading
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    HStack(spacing: skin.size.s6) {
                        Text(title).citadelFont("t13", weight: "medium").foregroundStyle(skin.color(skin.text.primary))
                        if let chip { chip }
                    }
                    if let detail {
                        Text(detail).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    }
                }
                Spacer(minLength: skin.size.s8)
                if let badge {
                    Text(badge).citadelFont("t10_5", weight: "bold", mono: true)
                        .foregroundStyle(skin.color(skin.palette.warning))
                        .frame(minWidth: skin.size.s20, minHeight: skin.size.s20)
                        .background(
                            skin.color(skin.palette.warning).opacity(skin.opacity.o16),
                            in: RoundedRectangle(cornerRadius: skin.size.s6))
                }
                if let hint { Text(hint).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)) }
                if checked {
                    Image(systemName: "checkmark").citadelFont("t11", weight: "bold")
                        .foregroundStyle(skin.color(skin.palette.accentPrimary))
                }
            }
            .padding(.horizontal, skin.size.s10)
            .padding(.vertical, skin.size.s6)
            .background(
                RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous)
                    .fill(hovering ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o45) : .clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}

/// A company's colour: the one the server stores (`color`, API minor 17) when set, else a prototype swatch
/// picked by id.
enum CompanyLook {
    /// `#rrggbb` as red, green and blue in 0...1; nil for anything else.
    static func rgb(_ text: String?) -> (red: Double, green: Double, blue: Double)? {
        guard let text, text.count == 7, text.hasPrefix("#"), let value = UInt32(text.dropFirst(), radix: 16) else {
            return nil
        }
        return (
            Double((value >> 16) & 0xFF) / 255, Double((value >> 8) & 0xFF) / 255, Double(value & 0xFF) / 255
        )
    }

    static func color(_ company: Components.Schemas.Company, skin: AinkradSkin) -> Color {
        if let rgb = rgb(company.color) { return Color(.sRGB, red: rgb.red, green: rgb.green, blue: rgb.blue) }
        let swatches: [AinkradColorToken] = [
            skin.palette.accentPrimary, skin.palette.success, skin.palette.accentViolet, skin.palette.warning,
            skin.palette.danger, skin.palette.accentSecondary,
        ]
        return skin.color(swatches[Int(company.id.magnitude % UInt64(swatches.count))])
    }
}

/// The dashed ＋ tile of the menu's "New company" row.
struct NewCompanyTile: View {
    let size: CGFloat
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
        Image(systemName: "plus").citadelFont("t13", weight: "semibold")
            .foregroundStyle(skin.color(skin.palette.accentPrimary))
            .frame(width: size, height: size)
            .overlay(
                shape.strokeBorder(
                    skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o50),
                    style: StrokeStyle(lineWidth: 1, dash: [skin.size.s4, skin.size.s3])))
    }
}
