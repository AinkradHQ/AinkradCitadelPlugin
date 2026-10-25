import AinkradAppKit
import SwiftUI

/// The plan's burndown as the prototype draws it (`burndown()`): a dashed ideal from the first day's points to zero
/// at the projected end, the points-left line with a soft cyan area under it, a "today" rule and a tip dot.
struct Burndown: View {
    let plan: PlanTree
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = skin.color(skin.palette.accentSecondary)
        let left = plan.burndown.map { Double($0.left) }
        Canvas { context, size in
            guard let start = left.first, start > 0, left.count > 0 else { return }
            let last = Double(left.count - 1)
            let days = Self.span(plan)
            let pad = size.height * 0.08
            func point(_ day: Double, _ value: Double) -> CGPoint {
                CGPoint(x: day / days * size.width, y: pad + (1 - value / start) * (size.height - pad * 2))
            }
            var ideal = Path()
            ideal.move(to: point(0, start))
            ideal.addLine(to: point(days, 0))
            context.stroke(
                ideal, with: .color(tint.opacity(skin.opacity.o60)),
                style: StrokeStyle(lineWidth: skin.size.s1_5, dash: [skin.size.s4, skin.size.s4]))
            var line = Path()
            for (day, value) in left.enumerated() {
                day == 0 ? line.move(to: point(0, value)) : line.addLine(to: point(Double(day), value))
            }
            var area = line
            area.addLine(to: CGPoint(x: point(last, 0).x, y: size.height))
            area.addLine(to: CGPoint(x: 0, y: size.height))
            area.closeSubpath()
            context.fill(
                area,
                with: .linearGradient(
                    Gradient(colors: [tint.opacity(skin.opacity.o16), tint.opacity(0)]), startPoint: .zero,
                    endPoint: CGPoint(x: 0, y: size.height)))
            context.stroke(line, with: .color(tint), style: StrokeStyle(lineWidth: skin.size.s2, lineCap: .round))
            let today = point(last, left.last ?? 0)
            var rule = Path()
            rule.move(to: CGPoint(x: today.x, y: 0))
            rule.addLine(to: CGPoint(x: today.x, y: size.height))
            context.stroke(
                rule, with: .color(skin.color(.palette("foreground", skin.opacity.o25))),
                style: StrokeStyle(lineWidth: skin.size.s1, dash: [skin.size.s3, skin.size.s3]))
            let dot = skin.size.s7
            context.fill(
                Path(ellipseIn: CGRect(x: today.x - dot / 2, y: today.y - dot / 2, width: dot, height: dot)),
                with: .color(tint))
        }
        .accessibilityLabel("Burndown: \(plan.points - plan.donePoints) points left")
    }

    /// Days from the first point to zero at the current pace (at least one past today).
    static func span(_ plan: PlanTree) -> Double {
        let last = Double(max(plan.burndown.count - 1, 0))
        return max(last + Double(plan.burndown.last?.left ?? 0) / max(plan.pointsPerDay, 0.1), last + 1)
    }
}
