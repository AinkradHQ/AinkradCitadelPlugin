// kit-candidate: K5 — a stacked bar whose segments grow in one after another, with its legend (7 pt squares, a muted
// label, a mono value). `AinkradStackedStatusBar` takes chart tones only and has no legend.
import AinkradAppKit
import SwiftUI

struct LegendSegment: Identifiable {
    var id: String { label }
    let label: String
    let value: Double
    let text: String
    let color: Color
}

/// `.rsd-stack` + `.rsd-leg`: 10 high, 2 pt gaps, r6; each segment scales in from the left, 90 ms apart.
struct LegendBar: View {
    let segments: [LegendSegment]
    var height: CGFloat?
    @State private var grown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shown = segments.filter { $0.value > 0 }
        let total = max(shown.reduce(0) { $0 + $1.value }, 0.0001)
        VStack(alignment: .leading, spacing: skin.size.s10) {
            GeometryReader { geo in
                let gaps = skin.size.s2 * CGFloat(max(shown.count - 1, 0))
                HStack(spacing: skin.size.s2) {
                    ForEach(Array(shown.enumerated()), id: \.element.id) { index, segment in
                        Rectangle().fill(segment.color)
                            .frame(width: max(0, (geo.size.width - gaps) * segment.value / total))
                            .scaleEffect(x: grown || reduceMotion ? 1 : 0, anchor: .leading)
                            .animation(
                                skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.7))
                                    .delay(Double(index) * 0.09 + 0.15), value: grown)
                    }
                }
            }
            .frame(height: height ?? skin.size.s10)
            .clipShape(RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous))
            AinkradFlowLayout(spacing: skin.size.s12, lineSpacing: skin.size.s4) {
                ForEach(segments) { segment in
                    HStack(spacing: skin.size.s5) {
                        RoundedRectangle(cornerRadius: skin.size.s2).fill(segment.color)
                            .frame(width: skin.size.s7, height: skin.size.s7)
                        Text(segment.label).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
                        Text(segment.text).citadelFont("t10_5", weight: "medium", mono: true)
                            .foregroundStyle(skin.color(skin.text.primary))
                    }
                }
            }
        }
        .onAppear { grown = true }
    }
}

/// A rounded tile holding an SF symbol (or any glyph view) in a tint: `.rk-i`, `.at-i`, `.rt-ic`, `.rd-ic`.
struct IconTile: View {
    let systemName: String
    let tint: Color
    var size: CGFloat?
    var radius: CGFloat?
    var filled = false
    var ring = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let side = size ?? skin.size.s32
        let shape = RoundedRectangle(cornerRadius: radius ?? side * 0.3, style: .continuous)
        Image(systemName: systemName)
            .citadelFont(
                side >= skin.size.s40 ? "t17" : side >= skin.size.s32 ? "t14" : side >= skin.size.s26 ? "t12" : "t10",
                weight: "semibold"
            )
            .foregroundStyle(filled ? skin.color(.palette("foreground", 1)) : tint)
            .frame(width: side, height: side)
            .background(shape.fill(filled ? tint : tint.opacity(skin.opacity.o15)))
            .overlay {
                if ring { shape.strokeBorder(tint.opacity(skin.opacity.o28), lineWidth: 1) }
            }
            .shadow(color: filled ? tint.opacity(skin.opacity.o45) : .clear, radius: skin.size.s6, y: skin.size.s4)
    }
}

/// The prototype's literal hues, mapped onto skin tokens (and two named figure palettes where the skin has none).
enum Hue {
    case blue, violet, green, cyan, pink, amber, slate, red, yellow

    func color(_ skin: AinkradSkin) -> Color {
        switch self {
        case .blue: skin.color(skin.palette.accentPrimary)
        case .violet: skin.color(skin.palette.accentViolet)
        case .green: skin.color(skin.palette.success)
        case .cyan: skin.color(skin.palette.accentSecondary)
        case .pink: AinkradFigurePalette.sakura.deepColor
        case .amber: AinkradFigurePalette.ember.lightColor
        case .slate: skin.color(skin.text.muted)
        case .red: skin.color(skin.palette.danger)
        case .yellow: skin.color(skin.palette.warning)
        }
    }

    init(_ tool: ToolLook.Hue) {
        switch tool {
        case .blue: self = .blue
        case .violet: self = .violet
        case .green: self = .green
        case .cyan: self = .cyan
        case .pink: self = .pink
        case .slate: self = .slate
        }
    }

    init(_ tone: RunLook.Tone) {
        switch tone {
        case .run: self = .cyan
        case .ok: self = .green
        case .warn: self = .yellow
        case .err: self = .red
        case .idle: self = .slate
        }
    }
}
