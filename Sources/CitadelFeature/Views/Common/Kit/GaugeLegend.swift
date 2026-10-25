import AinkradAppKit
import SwiftUI

/// `min · server X · max` under a gauge (10 pt mono, faint).
struct GaugeLegend: View {
    let low: String
    let middle: String
    let high: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack {
            Text(low)
            Spacer(minLength: skin.size.s4)
            Text(middle)
            Spacer(minLength: skin.size.s4)
            Text(high)
        }
        .citadelFont("t9_5", mono: true).foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
    }
}
