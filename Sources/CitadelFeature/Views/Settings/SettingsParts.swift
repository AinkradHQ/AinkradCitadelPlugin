import AinkradAppKit
import SwiftUI

extension CompanySettingsSection {
    /// The section's colour, as System Settings tints its icons. The prototype pins
    /// Notifications to pink #f472b6; the kit palette has no pink token, so it is
    /// carried as a hex token here (known gap, spec §4.0).
    static let notificationsPink: AinkradColorToken = .hex(0xF4 / 255.0, 0x72 / 255.0, 0xB6 / 255.0, 1.0)

    func tint(_ skin: AinkradSkin) -> Color {
        switch self {
        case .general: skin.color(skin.palette.accentPrimary)
        case .devices: skin.color(skin.palette.accentViolet)
        case .accounts: skin.color(skin.palette.warning)
        case .limits: skin.color(skin.palette.accentSecondary)
        case .notifications: skin.color(Self.notificationsPink)
        case .skills: skin.color(skin.palette.success)
        case .audit: skin.color(skin.text.muted)
        }
    }
}

/// A white glyph on a tinted gradient tile with a soft glow (`sx-ic`).
struct SectionGlyph: View {
    let icon: String
    let tint: Color
    let size: CGFloat
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Image(systemName: icon)
            .font(.system(size: size * 0.5, weight: .medium))  // design-lint: allow font-size scales-glyph
            .foregroundStyle(skin.color(.palette("foreground", 1)))
            .frame(width: size, height: size)
            .background(
                LinearGradient(
                    colors: [tint, tint.opacity(skin.opacity.o55)], startPoint: .topLeading, endPoint: .bottomTrailing),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous)
            )
            .shadow(color: tint.opacity(skin.opacity.o30), radius: size * 0.2, y: size * 0.1)
    }
}

/// A settings page's hero (`sxHero`): its glyph, the title and a line, an action on the right, on a tinted card with a
/// glow at the top-left.
struct SettingsHero<Action: View>: View {
    let section: CompanySettingsSection
    var title: String?
    var subtitle: String?
    @ViewBuilder let action: Action
    @State private var popped = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let tint = section.tint(skin)
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        HStack(spacing: skin.size.s16) {
            SectionGlyph(icon: section.icon, tint: tint, size: skin.size.s52)
                .scaleEffect(popped || reduceMotion ? 1 : 0.6)
                .opacity(popped || reduceMotion ? 1 : 0)
                .onAppear {
                    guard !popped, !reduceMotion else { return }
                    withAnimation(skin.animation(skin.motion.present)) { popped = true }
                }
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(title ?? section.title).citadelFont("t21", weight: "heavy").foregroundStyle(
                    skin.color(skin.text.primary))
                Text(subtitle ?? section.subtitle).citadelFont("t12_5").foregroundStyle(skin.color(skin.text.muted))
            }
            Spacer(minLength: skin.size.s10)
            action
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.vertical, skin.size.s18)
        .background(
            LinearGradient(
                colors: [
                    tint.citadelMix(with: skin.color(.palette("background", skin.opacity.o90)), fraction: 0.84),
                    skin.color(.palette("background", skin.opacity.o85)),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing), in: shape
        )
        .background(alignment: .topLeading) {
            Circle()
                .fill(
                    RadialGradient(
                        colors: [tint.opacity(skin.opacity.o35), .clear], center: .center, startRadius: 0,
                        endRadius: skin.size.s124)
                )
                .frame(width: skin.size.s250, height: skin.size.s250)
                .offset(x: -skin.size.s80, y: -skin.size.s140)
        }
        .clipShape(shape)
        .overlay(
            shape.strokeBorder(
                tint.citadelMix(with: skin.color(.palette("white", skin.opacity.o06)), fraction: 0.74), lineWidth: 1))
    }
}

extension SettingsHero where Action == EmptyView {
    init(section: CompanySettingsSection, title: String? = nil, subtitle: String? = nil) {
        self.init(section: section, title: title, subtitle: subtitle) { EmptyView() }
    }
}

/// A settings card (`sxCard`): an optional bold title with a faint hint on the right, then its rows.
struct SettingsCard<Content: View>: View {
    var title: String?
    var hint: String?
    var danger = false
    /// Seconds before the card rises in; pass `0.06 * index` to stagger a page's cards.
    var delay: Double = 0
    @ViewBuilder let content: Content
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        VStack(alignment: .leading, spacing: 0) {
            if title != nil || hint != nil {
                HStack(spacing: skin.size.s8) {
                    if let title {
                        Text(title).citadelFont("t13", weight: "bold")
                            .foregroundStyle(danger ? status.danger : skin.color(skin.text.primary))
                    }
                    Spacer(minLength: skin.size.s8)
                    if let hint { Text(hint).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)) }
                }
                .padding(.top, skin.size.s10)
                .padding(.bottom, skin.size.s6)
            }
            content
        }
        .padding(.horizontal, skin.size.s16)
        .padding(.top, skin.size.s6)
        .padding(.bottom, skin.size.s8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            LinearGradient(
                colors: [
                    danger
                        ? status.danger.opacity(skin.opacity.o07)
                        : skin.color(.palette("foreground", 0.045)),
                    skin.color(.palette("foreground", 0.02)),
                ], startPoint: .topLeading, endPoint: .bottomTrailing), in: shape
        )
        .overlay(
            shape.strokeBorder(
                danger ? status.danger.opacity(skin.opacity.o25) : skin.color(.palette("foreground", skin.opacity.o07)),
                lineWidth: 1)
        )
        .ainkradRiseIn(delay: delay)
    }
}

/// A native-feeling settings row (`sxRow`): the label and a faint hint on the left, the control on the right.
struct SettingsRow<Control: View>: View {
    let label: String
    var hint: String?
    @ViewBuilder let control: Control
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s16) {
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(label).citadelFont("t13", weight: "medium").foregroundStyle(skin.color(skin.text.primary))
                if let hint {
                    Text(hint).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            HStack(spacing: skin.size.s8) { control }
        }
        .padding(.vertical, skin.size.s11)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(skin.color(.palette("foreground", 0.04)))
                .frame(height: 1)  // design-lint: allow frame-literal 1pt separator matches sx-row box-shadow
                .allowsHitTesting(false)
        }
    }
}

/// "needs server": on a control the API cannot store yet (it is drawn, disabled).
struct ServerSoonChip: View {
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text("not stored yet").citadelFont("t10", mono: true).foregroundStyle(skin.color(skin.text.faint))
            .padding(.horizontal, skin.size.s6).padding(.vertical, skin.size.s1)
            .background(skin.color(.palette("foreground", skin.opacity.o05)), in: Capsule())
            .help("The Citadel server has no field for this yet")
            .fixedSize()
    }
}

/// A settings page: the hero, then its cards, in a scroll at most 1040 wide.
struct SettingsScroll<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s14) { content }
                .frame(maxWidth: skin.size.s860 + skin.size.s180, alignment: .leading)
                .padding(.horizontal, skin.size.s22)
                .padding(.top, skin.size.s18)
                .padding(.bottom, skin.size.s30)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .scrollIndicators(.never)
    }
}
