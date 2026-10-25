// kit-candidate: K13 — the three-dot "typing" bounce (`.typing`, `tdot 1.2s`, .15 s steps). The kit has none.
import AinkradAppKit
import SwiftUI

struct TypingDots: View {
    /// The bubble behind the dots (the requirement thread); bare dots inline in a system line.
    var bubble = true
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        TimelineView(.animation(paused: reduceMotion)) { context in
            let t = context.date.timeIntervalSinceReferenceDate
            HStack(spacing: skin.size.s4) {
                ForEach(0..<3, id: \.self) { index in
                    let phase = Self.phase(t - Double(index) * 0.15)
                    Circle().fill(skin.color(skin.text.muted))
                        .frame(width: skin.size.s6, height: skin.size.s6)
                        .opacity(reduceMotion ? skin.opacity.o60 : skin.opacity.o30 + (1 - skin.opacity.o30) * phase)
                        .offset(y: reduceMotion ? 0 : -skin.size.s3 * phase)
                }
            }
        }
        .padding(.horizontal, bubble ? skin.size.s14 : 0)
        .padding(.vertical, bubble ? skin.size.s10 : 0)
        .background(
            skin.color(.palette("foreground", bubble ? skin.opacity.o05 : 0)),
            in: RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        )
        .accessibilityLabel("typing")
    }

    /// 0 → 1 → 0 over the first 60 % of a 1.2 s cycle (`tdot`: peak at 30 %).
    static func phase(_ t: Double) -> Double {
        let p = (t.truncatingRemainder(dividingBy: 1.2) + 1.2).truncatingRemainder(dividingBy: 1.2) / 1.2
        guard p < 0.6 else { return 0 }
        return p < 0.3 ? p / 0.3 : (0.6 - p) / 0.3
    }
}
