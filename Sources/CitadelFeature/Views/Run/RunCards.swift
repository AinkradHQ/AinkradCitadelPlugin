import AinkradAppKit
import SwiftUI

/// `.rsd-card`: r16, a 3 % white fill, no border — the peek drawer's and the run rail's blocks.
struct RunPanel<Content: View>: View {
    var padding: CGFloat?
    @ViewBuilder let content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) { content }
            .padding(.horizontal, padding ?? skin.size.s14)
            .padding(.vertical, padding ?? skin.size.s12)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                skin.color(.palette("foreground", skin.opacity.o03)),
                in: RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous))
    }
}

/// `.rsd-ch`: a 12.5 bold title, a faint aside, a mono value trailing.
struct RunCardHead: View {
    let title: String
    var aside: String?
    var value: String?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s8) {
            Text(title).citadelFont("t12_5", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
            if let aside { Text(aside).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)) }
            Spacer(minLength: skin.size.s4)
            if let value {
                Text(value).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
            }
        }
    }
}

/// `.rk`: a KPI tile — an icon tile, the value over a faint label; brightens and lifts on hover.
struct KpiTile<Value: View>: View {
    let icon: String
    let tint: Color
    let label: String
    @ViewBuilder let value: Value
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: skin.size.s10) {
            IconTile(systemName: icon, tint: tint, size: skin.size.s32, radius: skin.size.s10)
            VStack(alignment: .leading, spacing: 0) {
                value.citadelFont("t15", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(1)
                Text(label).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
            }
            Spacer(minLength: 0)
        }
        .padding(skin.size.s12)
        .background(
            skin.color(.palette("foreground", hovering ? skin.opacity.o06 : skin.opacity.o03)),
            in: RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        )
        .offset(y: hovering && !reduceMotion ? -skin.size.s1 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// `.rsd-cx`: a context tile — icon tile, a faint label over a value; tappable ones brighten on hover.
struct ContextTile<Icon: View>: View {
    let label: String
    let value: Text
    var compact = false
    var action: (() -> Void)?
    @ViewBuilder let icon: Icon
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tile = HStack(spacing: compact ? skin.size.s8 : skin.size.s10) {
            icon
            VStack(alignment: .leading, spacing: 0) {
                Text(label).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                value.citadelFont(compact ? "t11" : "t12_5", weight: "medium")
                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, compact ? skin.size.s10 : skin.size.s12)
        .padding(.vertical, compact ? skin.size.s8 : skin.size.s10)
        .background(
            skin.color(
                .palette("foreground", hovering && action != nil ? skin.opacity.o06 : skin.opacity.o03)),
            in: RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        if let action {
            AinkradTapArea(action: action) { tile }
        } else {
            tile
        }
    }
}

extension ContextTile where Icon == ContextIcon {
    init(
        icon: String, tint: Color, label: String, value: Text, compact: Bool = false,
        action: (() -> Void)? = nil
    ) {
        self.init(label: label, value: value, compact: compact, action: action) {
            ContextIcon(systemName: icon, tint: tint, compact: compact)
        }
    }
}

/// A context tile's icon: 32 (r10), 26 (r8) in the rail's compact grid.
struct ContextIcon: View {
    let systemName: String
    let tint: Color
    var compact = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        IconTile(
            systemName: systemName, tint: tint, size: compact ? skin.size.s26 : skin.size.s32,
            radius: compact ? skin.size.s8 : skin.size.s10)
    }
}

/// `.rsd-chips` / `.chip`: 24 high, r7, a 7 % fill (12 % on hover when it opens something).
struct RunMetaChip<Content: View>: View {
    var action: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let chip = HStack(spacing: skin.size.s6) { content }
            .citadelFont("t11")
            .foregroundStyle(skin.color(skin.text.primary))
            .padding(.horizontal, skin.size.s9)
            .frame(height: skin.size.s24)
            .background(
                skin.color(
                    .palette("foreground", hovering && action != nil ? skin.opacity.o12 : skin.opacity.o07)),
                in: RoundedRectangle(cornerRadius: skin.size.s7, style: .continuous)
            )
            .onHover { hovering = $0 }
            .animation(skin.animation(skin.motion.hover), value: hovering)
        if let action {
            AinkradTapArea(action: action) { chip }
        } else {
            chip
        }
    }
}

/// `.rsd-out` / `.rq-st`: the outcome chip — glyph (or a glowing dot) and word in the tone, on its tint.
struct OutcomeChip: View {
    let text: String
    let tint: Color
    var glyph: String?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s6) {
            if let glyph {
                Text(glyph)
            } else {
                Circle().fill(tint).frame(width: skin.size.s7, height: skin.size.s7)
                    .shadow(color: tint, radius: skin.size.s4)
            }
            Text(text)
        }
        .citadelFont("t11", weight: "semibold")
        .foregroundStyle(tint)
        .padding(.horizontal, skin.size.s10)
        .frame(height: skin.size.s24)
        .background(
            tint.opacity(skin.opacity.o16), in: RoundedRectangle(cornerRadius: skin.size.s7, style: .continuous))
    }
}

/// The agent-palette pair a run's cards wash in (`--ca` / `--cb`).
extension AgentInfo {
    func washColors(_ skin: AinkradSkin) -> (Color, Color) { (palette.lightColor, palette.deepColor) }
}

extension View {
    /// The agent-palette wash of a run hero (`.rsd-hero`, `.run-hero`): a 135° gradient from `ca` through the dark
    /// base to `cb`, a `ca` rim, and two soft glows that drift.
    func runWash(_ colors: (Color, Color), radius: CGFloat, strength: Double = 1) -> some View {
        modifier(RunWash(colors: colors, radius: radius, strength: strength))
    }
}

private struct RunWash: ViewModifier {
    let colors: (Color, Color)
    let radius: CGFloat
    let strength: Double
    @State private var drift = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        content
            .background {
                ZStack {
                    shape.fill(
                        LinearGradient(
                            stops: [
                                .init(color: colors.0.opacity(skin.opacity.o20 * strength), location: 0),
                                .init(color: skin.color(.palette("background", skin.opacity.o85)), location: 0.6),
                                .init(color: colors.1.opacity(skin.opacity.o16 * strength), location: 1),
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                    GeometryReader { geo in
                        ZStack {
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [colors.0.opacity(skin.opacity.o35 * strength), .clear],
                                        center: .center,
                                        startRadius: 0, endRadius: skin.size.s128)
                                )
                                .frame(width: skin.size.s260, height: skin.size.s260)
                                .position(x: skin.size.s40, y: skin.size.s10)
                                .offset(x: drift ? skin.size.s30 : 0, y: drift ? skin.size.s16 : 0)
                            Circle()
                                .fill(
                                    RadialGradient(
                                        colors: [colors.1.opacity(skin.opacity.o30 * strength), .clear],
                                        center: .center,
                                        startRadius: 0, endRadius: skin.size.s110)
                                )
                                .frame(width: skin.size.s220, height: skin.size.s220)
                                .position(x: geo.size.width - skin.size.s50, y: geo.size.height + skin.size.s20)
                                .offset(x: drift ? -skin.size.s30 : 0, y: drift ? -skin.size.s16 : 0)
                        }
                    }
                    .clipShape(shape)
                }
            }
            .overlay(shape.strokeBorder(colors.0.opacity(skin.opacity.o30), lineWidth: 1))
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 7)).repeatForever(
                        autoreverses: true)
                ) { drift = true }
            }
    }
}
