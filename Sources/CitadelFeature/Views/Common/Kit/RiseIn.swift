// kit-candidate: `.ainkradRiseIn(delay:)` — the prototype's `rise` keyframe (from opacity 0, 8 pt down) with a
// per-item delay for staggered lists, cards and body sections. Skipped under Reduce Motion.
import AinkradAppKit
import SwiftUI

extension View {
    /// Fades in from a little below on first appearance, after `delay` seconds.
    func riseIn(delay: Double = 0, distance: CGFloat? = nil) -> some View {
        modifier(RiseIn(delay: delay, distance: distance))
    }
}

private struct RiseIn: ViewModifier {
    let delay: Double
    let distance: CGFloat?
    @State private var shown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content
            .opacity(shown || reduceMotion ? 1 : 0)
            .offset(y: shown || reduceMotion ? 0 : distance ?? skin.size.s8)
            .onAppear {
                guard !shown, !reduceMotion else { return }
                withAnimation(skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.35)).delay(delay)) {
                    shown = true
                }
            }
    }
}
