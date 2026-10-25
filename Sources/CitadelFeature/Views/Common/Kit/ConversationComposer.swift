// kit-candidate: K16 — the Citadel conversation composer (`.rq-composer`): a docked glass box with an optional "To"
// row, the speaker's orb, a bare auto-growing editor (↵ sends, ⇧↵ new line), attach and a gradient send button,
// and a hint line. `AinkradComposer` draws a bezelled field and no orb/To row; `AinkradTextArea` always bezels.
import AinkradAppKit
import SwiftUI

struct ConversationComposer<ToRow: View, Avatar: View>: View {
    @Binding var text: String
    let placeholder: String
    /// Amber border: the message answers an agent's open question.
    var isTargeted = false
    let hint: String
    var onAttach: (() -> Void)?
    let onSend: () -> Void
    @ViewBuilder var toRow: () -> ToRow
    @ViewBuilder var avatar: () -> Avatar
    @FocusState private var focused: Bool
    @State private var sendHover = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var canSend: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        VStack(alignment: .leading, spacing: skin.size.s8) {
            toRow()
            HStack(alignment: .bottom, spacing: skin.size.s10) {
                avatar().padding(.bottom, skin.size.s3)
                editor
                if let onAttach {
                    AinkradTapArea(help: "Attach a file", action: onAttach) {
                        Image(systemName: "paperclip").citadelFont("t14")
                            .foregroundStyle(skin.color(skin.text.muted))
                            .frame(width: skin.size.s34, height: skin.size.s34)
                            .contentShape(Rectangle())
                    }
                }
                sendButton
            }
            Text(hint).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                .padding(.leading, skin.size.s38)
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.top, skin.size.s10)
        .padding(.bottom, skin.size.s8)
        .background(shape.fill(skin.color(.palette("surfaceElevated", skin.opacity.o92))))
        .overlay(shape.strokeBorder(border, lineWidth: 1))
        .shadow(color: skin.color(.palette("black", skin.opacity.o20)), radius: skin.size.s15, y: -skin.size.s10)
        .animation(skin.animation(skin.motion.hover), value: focused)
        .animation(skin.animation(skin.motion.hover), value: isTargeted)
    }

    private var border: Color {
        if isTargeted { return status.warning.opacity(skin.opacity.o45) }
        if focused { return skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o45) }
        return skin.color(.palette("foreground", skin.opacity.o09))
    }

    private var editor: some View {
        BareTextEditor(text: $text, placeholder: placeholder, sizeKey: "t13", maxHeight: skin.size.s140, onReturn: send)
            .focused($focused)
    }

    private var sendButton: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        return AinkradTapArea(help: "Send ↵", action: send) {
            Image(systemName: "arrow.up").citadelFont("t14", weight: "semibold")
                .foregroundStyle(skin.color(skin.palette.white))
                .frame(width: skin.size.s34, height: skin.size.s34)
                .background(
                    shape.fill(
                        LinearGradient(
                            colors: [skin.color(skin.palette.accentPrimary), skin.color(skin.palette.accentViolet)],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .shadow(
                    color: skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o35), radius: skin.size.s6,
                    y: skin.size.s4
                )
                .opacity(canSend ? 1 : skin.opacity.o60)
        }
        .offset(y: sendHover && canSend && !reduceMotion ? -skin.size.s1 : 0)
        .onHover { sendHover = $0 }
        .animation(skin.animation(skin.motion.hover), value: sendHover)
    }

    private func send() {
        guard canSend else { return }
        onSend()
    }
}

/// The amber "To" chip of a composer: orb, label, ✕ to clear.
struct ComposerToChip<Avatar: View>: View {
    let label: String
    var onRemove: (() -> Void)?
    @ViewBuilder var avatar: () -> Avatar
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        HStack(spacing: skin.size.s6) {
            avatar()
            Text(label).citadelFont("t12").foregroundStyle(status.warning)
            if let onRemove {
                AinkradTapArea(help: "Remove", action: onRemove) {
                    Image(systemName: "xmark").citadelFont("t9_5", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.faint)).padding(.horizontal, skin.size.s4)
                        .frame(height: skin.size.s20).contentShape(Rectangle())
                }
            }
        }
        .padding(.leading, skin.size.s4)
        .padding(.trailing, skin.size.s6)
        .frame(height: skin.size.s26)
        .background(
            status.warning.opacity(skin.opacity.o14),
            in: RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous))
    }
}

/// A chrome-less multi-line editor that grows with its text (a hidden copy sizes it), with a faint placeholder.
/// `onReturn`, when set, makes ↵ call it and ⇧↵ insert a new line.
struct BareTextEditor: View {
    @Binding var text: String
    let placeholder: String
    var sizeKey = "t13"
    var weight: String?
    var maxHeight: CGFloat?
    var onReturn: (() -> Void)?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        let font = skin.font(AinkradFontToken(sizeKey: sizeKey, weight: weight), typography: typo)
        // The hidden copy sets the height; the editor and placeholder lie over it.
        Text(text.isEmpty ? " " : text + " ").font(font).lineSpacing(skin.size.s3)
            .padding(.vertical, skin.size.s8).padding(.horizontal, skin.size.s5)
            .frame(maxWidth: .infinity, alignment: .leading).hidden()
            .overlay(alignment: .topLeading) {
                if text.isEmpty {
                    Text(placeholder).font(font).foregroundStyle(skin.color(skin.text.faint))
                        .padding(.vertical, skin.size.s8).padding(.horizontal, skin.size.s5)
                        .allowsHitTesting(false)
                }
            }
            .overlay {
                TextEditor(text: $text)
                    .font(font).lineSpacing(skin.size.s3)
                    .foregroundStyle(skin.color(skin.text.primary))
                    .scrollContentBackground(.hidden)
                    .scrollIndicators(.never)
                    .padding(.vertical, skin.size.s8)
                    .onKeyPress(keys: [.return]) { press in
                        guard let onReturn, !press.modifiers.contains(.shift) else { return .ignored }
                        onReturn()
                        return .handled
                    }
            }
            .frame(minHeight: skin.size.s34, maxHeight: maxHeight ?? .infinity)
            .fixedSize(horizontal: false, vertical: true)
    }
}
