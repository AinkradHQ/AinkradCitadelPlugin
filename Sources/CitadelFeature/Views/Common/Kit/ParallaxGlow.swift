// kit-candidate: AinkradParallaxStage (spec 03 K8) — three radial glow layers (no blur) that drift slowly and lean
// against the cursor by different amounts: separated live layers, not one image moving.
import AinkradAppKit
import SwiftUI

struct ParallaxGlow: View {
    let light: Color
    let deep: Color
    /// The cursor in the stage, −0.5…0.5 each way; zero at rest.
    let cursor: CGPoint
    @State private var drift = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            ZStack(alignment: .topLeading) {
                blob(light.opacity(skin.opacity.o55), side: skin.size.s520)
                    .offset(
                        x: -skin.size.s160 + (drift ? skin.size.s60 : 0) - cursor.x * skin.size.s36,
                        y: -skin.size.s240 + (drift ? skin.size.s24 : 0) - cursor.y * skin.size.s26
                    )
                    .animation(drifting(16), value: drift)
                blob(deep.opacity(skin.opacity.o45), side: skin.size.s440)
                    .offset(
                        x: skin.size.s40 - (drift ? skin.size.s48 : 0) + cursor.x * skin.size.s28,
                        y: geo.size.height - skin.size.s440 + skin.size.s260 - (drift ? skin.size.s28 : 0)
                            + cursor.y * skin.size.s22
                    )
                    .animation(drifting(20), value: drift)
                blob(light.opacity(skin.opacity.o22), side: skin.size.s380)
                    .offset(x: geo.size.width * 0.96 - skin.size.s380 + cursor.x * skin.size.s18, y: -skin.size.s220)
            }
            .animation(
                reduceMotion ? nil : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.8)),
                value: cursor)
        }
        .allowsHitTesting(false)
        .onAppear { if !reduceMotion { drift = true } }
    }

    private func drifting(_ seconds: Double) -> Animation? {
        reduceMotion
            ? nil
            : skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: seconds)).repeatForever(
                autoreverses: true)
    }

    private func blob(_ color: Color, side: CGFloat) -> some View {
        RadialGradient(colors: [color, .clear], center: .center, startRadius: 0, endRadius: side / 2)
            .frame(width: side, height: side)
    }
}
