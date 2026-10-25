import AinkradAppKit
import SwiftUI

/// The docked reply (`.ap-dock`): an auto-growing reply over the action row — the side action, the shortcut hint,
/// then reject and the primary decision. It rises in; ⌘↵ approves and ⌘⌫ rejects, also while typing.
struct ApprovalDock<Side: View, Decision: View>: View {
    @Binding var reply: String
    let replyFocus: Int
    let placeholder: String
    let onApprove: () -> Void
    let onReject: () -> Void
    @ViewBuilder let side: Side
    @ViewBuilder let decision: Decision
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        VStack(alignment: .leading, spacing: skin.size.s8) {
            AinkradTextArea(
                text: $reply, placeholder: placeholder, minHeight: skin.size.s22, maxHeight: skin.size.s120,
                autoFocus: replyFocus > 0
            )
            .id(replyFocus)
            HStack(spacing: skin.size.s6) {
                side
                Spacer(minLength: skin.size.s8)
                Text("⌘↵ approve · ⌘⌫ reject").citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                decision
            }
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s10)
        .background(shape.fill(skin.color(.palette("background", skin.opacity.o90))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o09)), lineWidth: 1))
        .shadow(
            color: skin.color(skin.palette.black).opacity(skin.opacity.o20), radius: skin.size.s15, y: -skin.size.s10
        )
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.size.s14)
        .ainkradRiseIn(distance: skin.size.s14)
        .background {
            // ⌘↵ approves, ⌘⌫ rejects (the reply goes with either).
            Button("", action: onApprove)  // design-lint: allow raw-control hidden ⌘↵ claim
                .keyboardShortcut(.return, modifiers: .command).hidden()
            Button("", action: onReject)  // design-lint: allow raw-control hidden ⌘⌫ claim
                .keyboardShortcut(.delete, modifiers: .command).hidden()
        }
    }
}
