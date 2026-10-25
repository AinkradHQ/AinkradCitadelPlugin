// kit-candidate: AinkradBudgetBar with labelled ticks and a movable marker (spec 02 K11) — the prototype's
// `.ap-gauge`: a thick track, a green→amber fill that grows in, a "now" value above it, labelled warn / cap ticks
// under it, and an amber marker that slides to a proposed value. Plus `Sparkline` (the KPI tiles' 90×34 line).
import AinkradAppKit
import SwiftUI

struct GaugeTick {
    var fraction: Double
    var label: String
    var isCap = false
}

struct MarkerGauge: View {
    /// 0…1 of the track.
    let fill: Double
    let nowLabel: String
    let ticks: [GaugeTick]
    /// The proposed value's position, 0…1.
    var marker: Double?
    @State private var grown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let track = skin.size.s16
            let mid = skin.size.s26 + track / 2
            ZStack {
                Capsule().fill(skin.color(.palette("foreground", skin.opacity.o06)))
                    .frame(width: width, height: track).position(x: width / 2, y: mid)
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [skin.color(skin.palette.success), skin.color(skin.palette.warning)],
                            startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: width * clamp(fill), height: track)
                    .scaleEffect(x: grown || reduceMotion ? 1 : 0, anchor: .leading)
                    .position(x: width * clamp(fill) / 2, y: mid)
                Text(nowLabel).citadelFont("t12", weight: "semibold", mono: true)
                    .foregroundStyle(skin.color(skin.palette.warning))
                    .fixedSize()
                    .position(x: width * clamp(fill), y: skin.size.s8)
                ForEach(Array(ticks.enumerated()), id: \.offset) { _, tick in
                    let x = width * clamp(tick.fraction)
                    Rectangle()
                        .fill(
                            tick.isCap
                                ? skin.color(skin.palette.danger) : skin.color(.palette("foreground", skin.opacity.o35))
                        )
                        .frame(width: skin.size.s2, height: track + skin.size.s8)
                        .position(x: x, y: mid)
                    Text(tick.label).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
                        .fixedSize()
                        .position(x: x, y: mid + track + skin.size.s4)
                }
                if let marker {
                    RoundedRectangle(cornerRadius: skin.size.s3)
                        .fill(skin.color(skin.palette.warning))
                        .frame(width: skin.size.s4, height: skin.size.s28)
                        .shadow(color: skin.color(skin.palette.warning), radius: skin.size.s6)
                        .position(x: width * clamp(marker), y: mid)
                        .animation(
                            skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.15)), value: marker)
                }
            }
        }
        .frame(height: skin.size.s72)
        .padding(.horizontal, skin.size.s4)
        .onAppear {
            withAnimation(skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 1))) { grown = true }
        }
    }

    private func clamp(_ value: Double) -> Double { min(max(value, 0), 1) }
}

/// A small line through `values` (oldest first) with a dot on the newest.
struct Sparkline: View {
    let values: [Double]
    let tint: Color
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        GeometryReader { geo in
            let points = Self.points(values, in: geo.size, inset: skin.size.s4)
            Path { path in
                guard let first = points.first else { return }
                path.move(to: first)
                for point in points.dropFirst() { path.addLine(to: point) }
            }
            .stroke(tint, style: StrokeStyle(lineWidth: skin.size.s2_5, lineCap: .round, lineJoin: .round))
            if let last = points.last {
                Circle().fill(tint).frame(width: skin.size.s6, height: skin.size.s6)
                    .position(last)
            }
        }
        .frame(width: skin.size.s90, height: skin.size.s34)
    }

    static func points(_ values: [Double], in size: CGSize, inset: CGFloat) -> [CGPoint] {
        guard values.count > 1, let low = values.min(), let high = values.max() else { return [] }
        let span = max(high - low, 1)
        let step = (size.width - inset * 2) / CGFloat(values.count - 1)
        return values.enumerated().map { index, value in
            CGPoint(
                x: inset + CGFloat(index) * step,
                y: inset + (size.height - inset * 2) * CGFloat(1 - (value - low) / span))
        }
    }
}
