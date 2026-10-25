import AinkradAppKit
import SwiftUI

/// The prototype's `.val`: a value as a mono pill; click to edit in place. Return commits a value `validate` takes;
/// a refused one shakes, rings red and calls `onRefuse` (never clamped); Esc or leaving the field cancels.
struct ValPill: View {
    let text: String
    var isEditable = true
    var help: String?
    var validate: (String) -> Bool = { _ in true }
    var commit: (String) -> Void = { _ in }
    var onRefuse: (String) -> Void = { _ in }
    @State private var editing = false
    @State private var draft = ""
    @State private var refused = false
    @State private var shake: CGFloat = 0
    @State private var hovering = false
    @FocusState private var focused: Bool
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous)
        Group {
            if editing {
                AinkradTextField(text: $draft, placeholder: help ?? "", focus: $focused)
                    .compact().monospaced()
                    .onReturn { _ in submit() }
                    .frame(width: skin.size.s110)
                    .overlay(
                        shape.strokeBorder(status.danger, lineWidth: refused ? skin.size.s1_5 : 0)
                            .shadow(color: status.danger.opacity(refused ? skin.opacity.o30 : 0), radius: skin.size.s3)
                    )
                    .offset(x: shake)
                    .onExitCommand { editing = false }
                    .onChange(of: focused) { _, now in if !now { editing = false } }
                    .onAppear { focused = true }
            } else {
                AinkradTapArea(help: help, action: begin) {
                    Text(text).citadelFont("t12", mono: true).foregroundStyle(skin.color(skin.text.primary))
                        .padding(.horizontal, skin.size.s8)
                        .padding(.vertical, skin.size.s2)
                        .background(skin.color(.palette("background", 1)).opacity(skin.opacity.o22), in: shape)
                        .overlay(
                            shape.strokeBorder(
                                skin.color(skin.palette.accentSecondary).opacity(
                                    hovering && isEditable ? skin.opacity.o45 : 0),
                                lineWidth: 1))
                }
                .buttonStyle(.plain)
                .disabled(!isEditable)
                .onHover { hovering = $0 }
            }
        }
        .fixedSize()
    }

    private func begin() {
        draft = text
        refused = false
        editing = true
    }

    private func submit() {
        guard validate(draft) else {
            refused = true
            onRefuse(draft)
            // A shake: knocked aside, then a loose spring wobbles it back.
            shake = skin.size.s6
            withAnimation(skin.animation(AinkradAnimationToken(curve: "spring", response: 0.3, damping: 0.15))) {
                shake = 0
            }
            return
        }
        editing = false
        if draft != text { commit(draft) }
    }
}

/// The prototype's `.scope` chip: "↳ server" (inherited, faint) or "● company ↺" (set here, cyan, with reset).
struct SettingsScopeChip: View {
    let text: String
    let isOverridden: Bool
    var help: String?
    var reset: (() -> Void)?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let cyan = skin.color(skin.palette.accentSecondary)
        HStack(spacing: skin.size.s5) {
            Text(isOverridden ? "● \(text)" : "↳ \(text)").lineLimit(1)
            if isOverridden, let reset {
                AinkradTapArea(help: "Reset to the inherited value", action: reset) {
                    Text(verbatim: "↺").foregroundStyle(skin.color(skin.text.muted))
                }
                .buttonStyle(.plain)
            }
        }
        .citadelFont("t10", mono: true)
        .foregroundStyle(isOverridden ? cyan : skin.color(skin.text.faint))
        .padding(.horizontal, skin.size.s6)
        .padding(.vertical, skin.size.s1)
        .background(
            isOverridden ? cyan.opacity(skin.opacity.o12) : skin.color(.palette("foreground", skin.opacity.o05)),
            in: Capsule()
        )
        .help(help ?? "")
        .fixedSize()
    }
}
