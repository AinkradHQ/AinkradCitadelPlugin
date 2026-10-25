// kit-candidate: two small charts the kit lacks (spec 06 K2, K7) — a segmented donut whose arcs grow in staggered with
// a gap between them and any colour per segment, and a sparkline with a soft area fill under its line.
import AinkradAppKit
import SwiftUI

/// One arc of a `SegmentDonut`.
struct DonutSegment: Identifiable {
    let id: Int
    var value: Double
    var color: Color
}

/// Segmented ring (cost breakdown 140/16, accounts health 104/12): arcs grow over 1 s, 120 ms apart.
struct SegmentDonut<Center: View>: View {
    let segments: [DonutSegment]
    let diameter: CGFloat
    let lineWidth: CGFloat
    /// The gap between arcs, in points along the ring.
    var gap: CGFloat = 2
    @ViewBuilder let center: Center
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let total = max(segments.map(\.value).reduce(0, +), 0.000_1)
        let circumference = .pi * (diameter - lineWidth)
        let gapFraction = segments.count > 1 ? Double(gap / circumference) : 0
        var start = 0.0
        let arcs = segments.map { segment -> (DonutSegment, Double, Double) in
            let length = segment.value / total
            defer { start += length }
            return (segment, start, max(0, length - gapFraction))
        }
        return ZStack {
            Circle().stroke(skin.color(.palette("foreground", skin.opacity.o05)), lineWidth: lineWidth)
            ForEach(Array(arcs.enumerated()), id: \.element.0.id) { index, arc in
                DonutArc(
                    color: arc.0.color, from: arc.1, length: arc.2, lineWidth: lineWidth, delay: Double(index) * 0.12)
            }
            center
        }
        .frame(width: diameter, height: diameter)
        .padding(lineWidth / 2)
    }
}

private struct DonutArc: View {
    let color: Color
    let from: Double
    let length: Double
    let lineWidth: CGFloat
    let delay: Double
    @State private var shown = 0.0
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Circle()
            .trim(from: from, to: from + length * shown)
            .stroke(color, style: StrokeStyle(lineWidth: lineWidth, lineCap: .butt))
            .rotationEffect(.degrees(-90))
            .onAppear {
                guard !reduceMotion else {
                    shown = 1
                    return
                }
                withAnimation(skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 1)).delay(delay)) {
                    shown = 1
                }
            }
    }
}

/// A sparkline (`.cs-spark`): a 2 pt line over a 12 % area, scaled to its own max.
struct AreaSparkline: View {
    let values: [Double]
    let color: Color
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        ZStack {
            SparkShape(values: values, closed: true).fill(color.opacity(skin.opacity.o12))
            SparkShape(values: values, closed: false)
                .stroke(color, style: StrokeStyle(lineWidth: skin.size.s2, lineCap: .round, lineJoin: .round))
        }
    }
}

private struct SparkShape: Shape {
    let values: [Double]
    let closed: Bool

    func path(in rect: CGRect) -> Path {
        var path = Path()
        guard !values.isEmpty else { return path }
        let top = max(values.max() ?? 1, 1)
        let count = max(1, values.count - 1)
        let points = values.enumerated().map { index, value in
            CGPoint(
                x: rect.minX + rect.width * CGFloat(index) / CGFloat(count),
                y: rect.minY + rect.height * (1 - 0.06 - 0.8 * CGFloat(value / top)))
        }
        if closed {
            path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
            points.forEach { path.addLine(to: $0) }
            path.addLine(to: CGPoint(x: rect.maxX, y: rect.maxY))
            path.closeSubpath()
        } else {
            path.move(to: points[0])
            points.dropFirst().forEach { path.addLine(to: $0) }
        }
        return path
    }
}

/// A stacked share bar (`.ac-sb`): one coloured part per value with a small gap, growing in from the left.
struct ShareBar: View {
    let parts: [(value: Double, color: Color)]
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        GeometryReader { geo in
            let total = max(parts.map(\.value).reduce(0, +), 0.000_1)
            let gaps = skin.size.s2 * CGFloat(max(0, parts.count - 1))
            HStack(spacing: skin.size.s2) {
                ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                    Rectangle().fill(part.color)
                        .frame(width: max(0, (geo.size.width - gaps) * CGFloat(part.value / total)))
                }
            }
            .scaleEffect(x: shown ? 1 : 0, anchor: .leading)
        }
        .frame(height: skin.size.s6)
        .background(skin.color(.palette("foreground", skin.opacity.o05)))
        .clipShape(RoundedRectangle(cornerRadius: skin.size.s4))
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.7))) { shown = true }
            }
        }
    }
}

/// A plain progress track (`.bar` / `.tb`): a rounded fill of `fraction` in a faint track, growing in.
struct FillTrack: View {
    let fraction: Double
    let fill: AnyShapeStyle
    var height: CGFloat?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var shown = false

    var body: some View {
        let side = height ?? skin.size.s6
        GeometryReader { geo in
            Capsule().fill(fill)
                .frame(width: geo.size.width * CGFloat(min(max(fraction, 0), 1)) * (shown ? 1 : 0))
        }
        .frame(height: side)
        .background(Capsule().fill(skin.color(.palette("foreground", skin.opacity.o06))))
        .onAppear {
            if reduceMotion {
                shown = true
            } else {
                withAnimation(skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.7))) { shown = true }
            }
        }
    }
}
