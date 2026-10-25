// kit-candidate: K3 — an inset overlay drawer (scrim, glass panel offset from the window edges, crumb head with a
// trailing slot, content that cross-slides when it swaps, a footer). `ainkradDrawer` is full height with chamfer
// chrome and one entrance; Runs and Artifacts both peek with this.
import AinkradAppKit
import SwiftUI

/// The prototype's `.ak-drawer`: a scrim over the pane, the panel inset from the top (below the filter bar), right
/// and bottom, `min(760, 62%)` wide. Esc, ✕ and the scrim close it. `contentID` swaps the body with a short slide
/// instead of re-entering the panel.
struct PeekDrawer<ContentID: Hashable, Crumb: View, Trailing: View, Content: View, Foot: View>: View {
    let contentID: ContentID
    var top: CGFloat?
    let onClose: () -> Void
    @ViewBuilder let crumb: Crumb
    @ViewBuilder let trailing: Trailing
    @ViewBuilder let content: Content
    @ViewBuilder let foot: Foot
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geo in
            let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
            ZStack(alignment: .topTrailing) {
                skin.color(.palette("black", skin.opacity.o35))
                    .contentShape(Rectangle())
                    .onTapGesture(perform: onClose)
                    .transition(.opacity)
                VStack(spacing: 0) {
                    head
                    ScrollView {
                        content
                            .padding(.horizontal, skin.size.s16)
                            .padding(.bottom, skin.size.s16)
                            .id(contentID)
                            .transition(
                                reduceMotion ? .opacity : .offset(x: skin.size.s18).combined(with: .opacity))
                    }
                    .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: contentID)
                    foot
                }
                .frame(width: min(skin.size.s860 * 0.884, geo.size.width * 0.62))
                .background(shape.fill(skin.color(.palette("background", skin.opacity.o97))))
                .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o10)), lineWidth: 1))
                .clipShape(shape)
                .shadow(
                    color: skin.color(.palette("black", skin.opacity.o50)), radius: skin.size.s30, x: -skin.size.s20
                )
                .padding(.top, top ?? skin.size.s56)
                .padding(.trailing, skin.size.s20)
                .padding(.bottom, skin.size.s20)
                .transition(.offset(x: skin.size.s60).combined(with: .opacity))
            }
        }
    }

    private var head: some View {
        HStack(spacing: skin.size.s8) {
            crumb
            Spacer(minLength: skin.size.s8)
            trailing
            DrawerCloseButton(action: onClose)
        }
        .padding(.horizontal, skin.size.s16)
        .padding(.vertical, skin.size.s14)
    }
}

/// `Runs › #422`: faint crumbs, the last one in mono foreground.
struct DrawerCrumb: View {
    let parts: [String]
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s6) {
            ForEach(Array(parts.enumerated()), id: \.offset) { index, part in
                if index > 0 { Text("›").foregroundStyle(skin.color(skin.text.faint)) }
                if index == parts.count - 1 {
                    Text(part).citadelFont("t12", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary))
                } else {
                    Text(part).foregroundStyle(skin.color(skin.text.faint))
                }
            }
        }
        .citadelFont("t12")
    }
}

/// The drawer's and Quick Look's square ✕ (and ‹ › pager) button: faint, a soft fill on hover.
struct DrawerCloseButton: View {
    var glyph = "xmark"
    var size: CGFloat?
    var isEnabled = true
    var filled = false
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let side = size ?? skin.size.s30
        AinkradTapArea(help: glyph == "xmark" ? "Close (Esc)" : nil, action: action) {
            Image(systemName: glyph)
                .citadelFont(glyph == "xmark" ? "t11" : "t12", weight: "semibold")
                .foregroundStyle(skin.color(hovering ? skin.text.primary : skin.text.muted))
                .frame(width: side, height: side)
                .background(
                    skin.color(
                        .palette(
                            "foreground",
                            hovering ? skin.opacity.o12 : filled ? skin.opacity.o06 : 0)),
                    in: RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous)
                )
                .contentShape(Rectangle())
        }
        .opacity(isEnabled ? 1 : skin.opacity.o30)
        .disabled(!isEnabled)
        .onHover { hovering = $0 && isEnabled }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .modifier(EscapeShortcut(isOn: glyph == "xmark"))
    }
}

private struct EscapeShortcut: ViewModifier {
    let isOn: Bool
    func body(content: Content) -> some View {
        if isOn { content.keyboardShortcut(.cancelAction) } else { content }
    }
}
