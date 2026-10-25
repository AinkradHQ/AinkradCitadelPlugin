import AinkradAppKit
import SwiftUI

/// The prototype's bento tile (`.hm .tile`): r18, a faint top-lit glass fill and a hairline rim that brightens on
/// hover. Optional tap lifts it.
struct BentoTile<Content: View>: View {
    var padding: CGFloat?
    var tint: Color?
    var onTap: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        content
            .padding(padding ?? skin.size.s16)
            .frame(maxWidth: .infinity, alignment: .topLeading)
            .background(
                shape.fill(
                    LinearGradient(
                        colors: [
                            (tint ?? skin.color(.palette("foreground", 1))).opacity(
                                tint == nil ? 0.045 : skin.opacity.o10),
                            skin.color(.palette("foreground", 0.02)),
                        ], startPoint: .top, endPoint: .bottom))
            )
            .overlay(
                shape.strokeBorder(
                    (tint ?? skin.color(.palette("foreground", 1)))
                        .opacity(tint == nil ? (hovering ? skin.opacity.o12 : skin.opacity.o07) : skin.opacity.o25),
                    lineWidth: 1)
            )
            .contentShape(shape)
            .offset(y: hovering && onTap != nil && !reduceMotion ? -skin.size.s2 : 0)
            .onHover { hovering = $0 }
            .animation(skin.animation(skin.motion.hover), value: hovering)
            .onTapGesture { onTap?() }
    }
}

/// `What needs you now [8]                Open inbox →`.
struct SectionHead: View {
    let title: String
    var count: String?
    var link: String?
    var perform: () -> Void = {}
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s8) {
            Text(title).citadelFont("t10_5", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
            if let count {
                Text(count).citadelFont("t10", weight: "semibold", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary))
                    .padding(.horizontal, skin.size.s7)
                    .padding(.vertical, skin.size.s1)
                    .background(skin.color(.palette("foreground", skin.opacity.o07)), in: Capsule())
            }
            Spacer(minLength: skin.size.s8)
            if let link {
                AinkradTapArea(action: perform) {
                    Text(link).citadelFont("t11", weight: "medium").foregroundStyle(
                        skin.color(skin.palette.accentSecondary))
                }
                .buttonStyle(.plain)
            }
        }
    }
}

/// A 30 pt rounded glyph tile tinted by tone (needs-you kinds, activity events).
struct KindTile: View {
    let glyph: String
    let tint: Color
    var size: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let side = size ?? skin.size.s30
        Text(glyph).citadelFont("t12", weight: "semibold").foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(
                tint.opacity(skin.opacity.o16), in: RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
            )
            .overlay(
                RoundedRectangle(cornerRadius: side * 0.3, style: .continuous)
                    .strokeBorder(tint.opacity(skin.opacity.o20), lineWidth: 1))
    }
}

/// A run's harness as the prototype's two-letter tag (Cl, Cx, Oc, Ag) in its colour.
struct HarnessTag: View {
    let harness: String
    var size: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let side = size ?? skin.size.s30
        let tint = AgentLook.harness(harness)?.color ?? skin.color(skin.text.muted)
        Text(Self.letters(harness)).citadelFont(side > skin.size.s28 ? "t12" : "t10", weight: "bold", mono: true)
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(
                tint.opacity(skin.opacity.o16), in: RoundedRectangle(cornerRadius: side * 0.3, style: .continuous))
    }

    static func letters(_ harness: String) -> String {
        switch harness.lowercased() {
        case let h where h.hasPrefix("claude"): "Cl"
        case let h where h.hasPrefix("codex"): "Cx"
        case let h where h.hasPrefix("opencode"): "Oc"
        default: "Ag"
        }
    }
}

/// A small status pill (`.pill.ok/warn/err/run`): optional leading dot.
struct StatePill: View {
    let text: String
    let tint: Color
    var dot = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s5) {
            if dot { Circle().fill(tint).frame(width: skin.size.s6, height: skin.size.s6) }
            Text(text).citadelFont("t10_5", weight: "medium")
        }
        .foregroundStyle(tint)
        .padding(.horizontal, skin.size.s8)
        .padding(.vertical, skin.size.s2)
        .background(tint.opacity(skin.opacity.o14), in: Capsule())
    }
}
