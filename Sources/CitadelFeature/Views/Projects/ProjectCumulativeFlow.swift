import AinkradAppKit
import SwiftUI

/// The cumulative flow (`qReports` `band()`): issues per state at each day's end, stacked from Done at the bottom to
/// To do at the top, each band a translucent area in its state's colour. A small local chart: the kit has no
/// stacked area.
struct ProjectsCumulativeFlow: View {
    let points: [CfdPoint]
    @Environment(\.ainkradSkin) private var skin

    /// Bottom to top.
    private static let bands: [(state: String, count: KeyPath<CfdPoint, Int>)] = [
        ("done", \.done), ("review", \.review), ("in_progress", \.active), ("todo", \.todo),
    ]

    var body: some View {
        GeometryReader { geo in
            let top = CGFloat(max(1, points.map(\.total).max() ?? 1))
            let x = { (i: Int) in points.count > 1 ? CGFloat(i) / CGFloat(points.count - 1) * geo.size.width : 0 }
            let y = { (v: Int) in geo.size.height * (1 - CGFloat(v) / top) }
            ZStack {
                ForEach(Array(Self.bands.enumerated()), id: \.offset) { index, band in
                    let below = Self.bands.prefix(index).map(\.count)
                    let lower = { (p: CfdPoint) in below.reduce(0) { $0 + p[keyPath: $1] } }
                    Path { path in
                        for (i, p) in points.enumerated() {
                            let point = CGPoint(x: x(i), y: y(lower(p) + p[keyPath: band.count]))
                            if i == 0 { path.move(to: point) } else { path.addLine(to: point) }
                        }
                        for (i, p) in points.enumerated().reversed() {
                            path.addLine(to: CGPoint(x: x(i), y: y(lower(p))))
                        }
                        path.closeSubpath()
                    }
                    .fill(ProjectLook.flowTint(band.state, skin: skin).opacity(skin.opacity.o55))
                }
            }
        }
    }
}
