// kit-candidate: the stacked bar chart the Cost screen needs and `AinkradBarChart` lacks (spec 06 K6) — gradient or
// flat segments per bar, bars that grow in staggered 22 ms, hover brightening with a floating tooltip, and an optional
// dashed threshold line.
import AinkradAppKit
import SwiftUI

/// One segment of a bar, bottom first.
struct StackedSegment {
    var value: Double
    var fill: AnyShapeStyle
}

/// One bar: its segments bottom to top.
struct StackedBar: Identifiable {
    let id: Int
    var segments: [StackedSegment]
    var total: Double { segments.map(\.value).reduce(0, +) }
}

struct StackedBarChart<Tip: View>: View {
    let bars: [StackedBar]
    /// A dashed line at this value (the warn line), in the bars' unit.
    var threshold: Double?
    var thresholdColor: Color?
    @ViewBuilder let tooltip: (Int) -> Tip
    @State private var hovered: Int?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        GeometryReader { geo in
            let count = max(bars.count, 1)
            let step = geo.size.width / CGFloat(count)
            let width = min(skin.size.s26, step * 0.62)
            let top = max(threshold ?? 0, bars.map(\.total).max() ?? 0, 0.000_1) * 1.1
            let usable = geo.size.height - skin.size.s8
            ZStack(alignment: .topLeading) {
                if let threshold, threshold > 0 {
                    let y = geo.size.height - usable * CGFloat(threshold / top)
                    Path { path in
                        path.move(to: CGPoint(x: 0, y: y))
                        path.addLine(to: CGPoint(x: geo.size.width, y: y))
                    }
                    .stroke(
                        (thresholdColor ?? skin.color(skin.palette.warning)).opacity(skin.opacity.o70),
                        style: StrokeStyle(lineWidth: 1, dash: [skin.size.s4, skin.size.s5]))
                }
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(bars) { bar in
                        BarColumn(
                            bar: bar, width: width, scale: usable / CGFloat(top), isHovered: hovered == bar.id,
                            delay: Double(bar.id) * 0.022
                        )
                        .frame(width: step, height: geo.size.height, alignment: .bottom)
                        .contentShape(Rectangle())
                        .onHover { inside in
                            if inside {
                                hovered = bar.id
                            } else if hovered == bar.id {
                                hovered = nil
                            }
                        }
                    }
                }
                if let hovered, let index = bars.firstIndex(where: { $0.id == hovered }) {
                    tooltip(hovered)
                        .fixedSize()
                        .offset(
                            x: min(step * CGFloat(index) + step, geo.size.width - skin.size.s190),
                            y: skin.size.s4
                        )
                        .allowsHitTesting(false)
                        .transition(.opacity)
                }
            }
        }
        .animation(skin.animation(skin.motion.hover), value: hovered)
    }
}

private struct BarColumn: View {
    let bar: StackedBar
    let width: CGFloat
    let scale: CGFloat
    let isHovered: Bool
    let delay: Double
    @State private var grown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: skin.size.s1_5) {
            ForEach(Array(bar.segments.enumerated().reversed()), id: \.offset) { _, segment in
                if segment.value > 0 {
                    RoundedRectangle(cornerRadius: skin.size.s3, style: .continuous)
                        .fill(segment.fill)
                        .frame(width: width, height: max(skin.size.s1, CGFloat(segment.value) * scale - skin.size.s1_5))
                }
            }
        }
        .brightness(isHovered ? 0.18 : 0)
        .scaleEffect(y: grown ? 1 : 0, anchor: .bottom)
        .onAppear {
            guard !reduceMotion else {
                grown = true
                return
            }
            withAnimation(skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.55)).delay(delay)) {
                grown = true
            }
        }
    }
}

/// `.ctip`: the chart's floating tooltip card.
struct ChartTip<Content: View>: View {
    @ViewBuilder let content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        VStack(alignment: .leading, spacing: skin.size.s3) { content }
            .citadelFont("t11")
            .padding(.horizontal, skin.size.s11)
            .padding(.vertical, skin.size.s9)
            .frame(minWidth: skin.size.s168, alignment: .leading)
            .background(shape.fill(skin.color(.palette("background", skin.opacity.o95))))
            .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
            .shadow(color: skin.color(.palette("black", skin.opacity.o50)), radius: skin.size.s12, y: skin.size.s10)
    }
}

/// A legend swatch: an 8 pt rounded square and its label.
struct LegendSwatch: View {
    let color: Color
    let label: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s5) {
            RoundedRectangle(cornerRadius: skin.size.s2).fill(color).frame(width: skin.size.s8, height: skin.size.s8)
            Text(label)
        }
    }
}
