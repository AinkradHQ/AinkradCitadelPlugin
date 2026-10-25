// kit-candidate: AinkradHeatmap (spec 03 K6) — rows × columns of cells whose fill strength is the value, with row
// and column labels, fading in cell by cell.
import AinkradAppKit
import SwiftUI

struct Heatmap: View {
    let rows: [String]
    let columns: [String]
    /// `values[row][column]`.
    let values: [[Int]]
    var tint: Color?
    @State private var shown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let peak = max(1, values.flatMap { $0 }.max() ?? 1)
        let color = tint ?? skin.color(skin.palette.accentSecondary)
        Grid(horizontalSpacing: skin.size.s4, verticalSpacing: skin.size.s4) {
            GridRow {
                Color.clear.frame(width: skin.size.s30, height: skin.size.s1)
                ForEach(columns, id: \.self) { Text($0).frame(maxWidth: .infinity) }
            }
            ForEach(Array(rows.enumerated()), id: \.offset) { r, row in
                GridRow {
                    Text(row).frame(width: skin.size.s30, alignment: .leading)
                    ForEach(Array(columns.indices), id: \.self) { c in
                        let v = Double(values[safe: r]?[safe: c] ?? 0) / Double(peak)
                        RoundedRectangle(cornerRadius: skin.size.s4)
                            .fill(color.opacity(skin.opacity.o07 + v * skin.opacity.o75))
                            .frame(maxWidth: .infinity, minHeight: skin.size.s16, maxHeight: skin.size.s16)
                            .opacity(shown || reduceMotion ? 1 : 0)
                            .animation(
                                skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.4))
                                    .delay(Double(r * columns.count + c) * 0.018), value: shown
                            )
                            .help("\(row) \(columns[c]):00 · \(values[safe: r]?[safe: c] ?? 0) runs")
                    }
                }
            }
        }
        .citadelFont("t9_5", mono: true)
        .foregroundStyle(skin.color(skin.text.faint))
        .onAppear { shown = true }
    }
}

extension Array {
    subscript(safe index: Int) -> Element? { indices.contains(index) ? self[index] : nil }
}
