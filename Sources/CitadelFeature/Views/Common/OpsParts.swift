import AinkradAppKit
import AppKit
import SwiftUI

extension Color {
    /// Linear blend of two colours in sRGB — equivalent to CSS `color-mix(in srgb, self (1-f), other f)`.
    /// Replaces `Color.mix(with:by:)` which resolves to the macOS 15.0-only `mix(with:by:in:)` in the macOS 27 SDK.
    func citadelMix(with other: Color, fraction: CGFloat) -> Color {
        let a = NSColor(self).usingColorSpace(.deviceRGB) ?? .clear
        let b = NSColor(other).usingColorSpace(.deviceRGB) ?? .clear
        return Color(nsColor: a.blended(withFraction: fraction, of: b) ?? b)  // design-lint: allow raw-color blend
    }
}

/// The operations drawers' hero (`dr-hero`): a tinted card with a glow at the top-left, the leading tile, a mono
/// title over a faint line, and an optional state pill on the right.
struct DrawerHero<Leading: View>: View {
    let tint: Color
    let title: String
    let subtitle: String
    var pill: (text: String, tint: Color)?
    @ViewBuilder let leading: Leading
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        HStack(spacing: skin.size.s14) {
            leading
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(title).citadelFont("t16", weight: "bold", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                Text(subtitle).citadelFont("t12").foregroundStyle(skin.color(skin.text.faint)).lineLimit(2)
            }
            Spacer(minLength: skin.size.s8)
            if let pill { StatePillBox(text: pill.text, tint: pill.tint) }
        }
        .padding(skin.size.s16)
        .background(
            LinearGradient(
                colors: [
                    tint.citadelMix(with: skin.color(.palette("background", skin.opacity.o90)), fraction: 0.84),
                    skin.color(.palette("background", skin.opacity.o85)),
                ],
                startPoint: .topLeading, endPoint: .bottomTrailing), in: shape
        )
        .background(alignment: .topLeading) {
            Circle().fill(
                RadialGradient(
                    colors: [tint.opacity(skin.opacity.o30), .clear], center: .center, startRadius: 0,
                    endRadius: skin.size.s96)
            )
            .frame(width: skin.size.s200, height: skin.size.s200)
            .offset(x: -skin.size.s60, y: -skin.size.s110)
        }
        .clipShape(shape)
        .overlay(shape.strokeBorder(tint.citadelMix(with: Color.clear, fraction: 0.74), lineWidth: 1))
    }
}

/// The prototype's `rn-st` / `ac-hb` pill: h26, r8, a glowing dot and the state word in its colour.
struct StatePillBox: View {
    let text: String
    let tint: Color
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s6) {
            Circle().fill(tint).frame(width: skin.size.s6, height: skin.size.s6).shadow(
                color: tint, radius: skin.size.s8)
            Text(text).citadelFont("t11", weight: "semibold")
        }
        .foregroundStyle(tint)
        .padding(.horizontal, skin.size.s10)
        .frame(height: skin.size.s26)
        .background(
            tint.opacity(skin.opacity.o14), in: RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous))
    }
}

/// A drawer section card (`dl-sec`): a bold title with a faint hint on the right, then its content.
struct DrawerSection<Content: View>: View {
    var title: String?
    var hint: String?
    @ViewBuilder let content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            if title != nil || hint != nil {
                HStack(alignment: .firstTextBaseline, spacing: skin.size.s10) {
                    if let title {
                        Text(title).citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                    }
                    Spacer(minLength: skin.size.s8)
                    if let hint { Text(hint).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)) }
                }
            }
            content
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(skin.size.s14)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)),
            in: RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
                .strokeBorder(skin.color(.palette("white", skin.opacity.o05)), lineWidth: 1))
    }
}

/// A command on a dark strip (`ops-cmd`): cyan mono text that scrolls sideways, and Copy → "Copied ✓".
struct CommandStrip: View {
    let command: String
    @State private var copied = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s10) {
            ScrollView(.horizontal) {
                Text(verbatim: command).citadelFont("t12", mono: true)
                    .foregroundStyle(skin.color(skin.palette.accentSecondary))
                    .textSelection(.enabled)
                    .fixedSize()
            }
            .scrollIndicators(.never)
            AinkradDockButton(copied ? "Copied ✓" : "Copy", systemImage: "doc.on.doc", height: skin.size.s30) {
                NSPasteboard.general.clearContents()
                NSPasteboard.general.setString(command, forType: .string)
                copied = true
                Task {
                    try? await Task.sleep(for: .seconds(1.5))
                    copied = false
                }
            }
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.vertical, skin.size.s10)
        .background(
            skin.color(.palette("background", 1)).opacity(skin.opacity.o35),
            in: RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
                .strokeBorder(skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
    }
}

/// A filter chip (`sx-chip`, `lg-f`): h30 r9; on = its tint washed with a coloured rim. An optional count in mono.
struct FilterChip: View {
    let title: String
    var count: Int?
    var tint: Color?
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let color = tint ?? skin.color(skin.palette.accentPrimary)
        let shape = RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous)
        AinkradTapArea(action: action) {
            HStack(spacing: skin.size.s6) {
                Text(title).citadelFont("t12")
                if let count {
                    Text(verbatim: "\(count)").citadelFont("t10_5", weight: "semibold", mono: true)
                        .foregroundStyle(tint ?? skin.color(skin.text.faint))
                }
            }
            .foregroundStyle(skin.color(isOn || hovering ? skin.text.primary : skin.text.muted))
            .padding(.horizontal, skin.size.s12)
            .frame(height: skin.size.s30)
            .background(
                isOn ? color.opacity(skin.opacity.o16) : skin.color(.palette("foreground", skin.opacity.o05)), in: shape
            )
            .overlay(
                shape.strokeBorder(
                    isOn ? color.opacity(skin.opacity.o45) : skin.color(.palette("foreground", skin.opacity.o07)),
                    lineWidth: 1))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: isOn)
    }
}

/// A choice card in a grid (`aa-prov`): the tile, a title and a faint line; on = tinted with a coloured rim. Lifts on
/// hover.
struct ChoiceCard<Leading: View>: View {
    let title: String
    let detail: String
    let tint: Color
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder let leading: Leading
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        AinkradTapArea(action: action) {
            VStack(spacing: skin.size.s6) {
                leading
                Text(title).citadelFont("t12_5", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                Text(detail).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                    .multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, skin.size.s14)
            .padding(.horizontal, skin.size.s8)
            .background(
                isOn ? tint.opacity(skin.opacity.o12) : skin.color(.palette("background", 1)).opacity(skin.opacity.o18),
                in: shape
            )
            .overlay(
                shape.strokeBorder(
                    isOn ? tint.opacity(skin.opacity.o55) : skin.color(.palette("foreground", skin.opacity.o06)),
                    lineWidth: 1)
            )
            .shadow(color: isOn ? tint.opacity(skin.opacity.o18) : .clear, radius: skin.size.s24, y: skin.size.s8)
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .ainkradHoverLift(skin.size.s2, cornerRadius: skin.size.s14)
        .animation(skin.animation(skin.motion.hover), value: isOn)
    }
}

/// A numbered "what it does" row (`ar-what`): a blue disc, a bold line and a faint one.
struct NumberedRow: View {
    let number: Int
    let title: String
    let detail: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s12) {
            Text(verbatim: "\(number)").citadelFont("t11", weight: "bold", mono: true)
                .foregroundStyle(skin.color(skin.palette.accentPrimary))
                .frame(width: skin.size.s24, height: skin.size.s24)
                .background(skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o15), in: Circle())
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(title).citadelFont("t12_5", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                Text(detail).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s10)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)),
            in: RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous))
    }
}
