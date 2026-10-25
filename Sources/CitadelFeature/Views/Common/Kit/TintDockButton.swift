// kit-candidate: an `AinkradDockButton` tone taking any colour (spec 02 K4) — Why stuck's recommended fix
// (`.sk-fix .dk.pri`: the card colour at 22% over a faint fill, 45% rim, white label), with a busy state that
// swaps the label for a spinner and "Retrying…".
import AinkradAppKit
import SwiftUI

struct TintDockButton: View {
    let title: String
    let tint: Color
    /// Shown with a spinner in place of `title` while the action runs.
    var busyTitle: String?
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        AinkradTapArea(action: { if busyTitle == nil { action() } }) {
            HStack(spacing: skin.size.s6) {
                if busyTitle != nil { ProgressView().controlSize(.small) }
                Text(busyTitle ?? title).citadelFont("t12", weight: "medium")
            }
            .foregroundStyle(skin.color(.palette("foreground", 1)))
            .padding(.horizontal, skin.size.s12)
            .frame(height: skin.size.s34)
            .background(
                ZStack {
                    shape.fill(skin.color(.palette("foreground", skin.opacity.o05)))
                    shape.fill(tint.opacity(hovering ? skin.opacity.o30 : skin.opacity.o22))
                }
            )
            .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o45), lineWidth: 1))
            .contentShape(shape)
        }
        .offset(y: hovering && !reduceMotion ? -skin.size.s2 : 0)
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .onHover { hovering = $0 }
    }
}
