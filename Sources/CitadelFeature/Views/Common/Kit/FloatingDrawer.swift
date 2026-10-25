// kit-candidate: K5 — a floating, inset drawer (r20 panel, scrim, slide-in, header slot, close, Esc). The kit's
// `.ainkradDrawer` is edge-attached and width-only; Citadel's requirement / run drawers float inside the pane.
import AinkradAppKit
import SwiftUI

extension View {
    /// Floats `content` in a drawer over this view's trailing side: a scrim behind (tap closes), a header row with
    /// `header` and ✕, a scrolling body and an optional pinned `footer`. Esc closes. Slides in from the right
    /// (a fade under Reduce Motion).
    func floatingDrawer<Header: View, Body: View, Footer: View>(
        isPresented: Bool, onClose: @escaping () -> Void, @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Body, @ViewBuilder footer: @escaping () -> Footer
    ) -> some View {
        modifier(
            FloatingDrawerModifier(
                isPresented: isPresented, onClose: onClose, header: header, drawerBody: content, footer: footer))
    }
}

private struct FloatingDrawerModifier<Header: View, DrawerBody: View, Footer: View>: ViewModifier {
    let isPresented: Bool
    let onClose: () -> Void
    @ViewBuilder let header: () -> Header
    @ViewBuilder let drawerBody: () -> DrawerBody
    @ViewBuilder let footer: () -> Footer
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    if isPresented {
                        skin.color(.palette("background", skin.opacity.o35))
                            .contentShape(Rectangle())
                            .onTapGesture(perform: onClose)
                            .transition(.opacity)
                        panel(width: min(skin.size.s380 * 2, geo.size.width * 0.62))
                            .padding(.top, skin.size.s110)
                            .padding(.trailing, skin.size.s34)
                            .padding(.bottom, skin.size.s34)
                            .transition(
                                reduceMotion ? .opacity : .opacity.combined(with: .offset(x: skin.size.s60)))
                    }
                }
                .animation(
                    reduceMotion
                        ? nil : skin.animation(AinkradAnimationToken(curve: "spring", response: 0.35, damping: 0.82)),
                    value: isPresented)
            }
        }
    }

    private func panel(width: CGFloat) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        return VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: skin.size.s10) {
                header()
                Spacer(minLength: skin.size.s8)
                AinkradTapArea(help: "Close (Esc)", action: onClose) {
                    Image(systemName: "xmark").citadelFont("t12", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.muted))
                        .frame(width: skin.size.s30, height: skin.size.s30)
                        .background(
                            skin.color(.palette("foreground", skin.opacity.o06)),
                            in: RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous))
                }
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal, skin.size.s16)
            .padding(.vertical, skin.size.s14)
            ScrollView {
                drawerBody()
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, skin.size.s16)
                    .padding(.bottom, skin.size.s16)
            }
            footer()
        }
        .frame(width: width)
        .frame(maxHeight: .infinity)
        .background(shape.fill(skin.color(.palette("background", skin.opacity.o97))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o10)), lineWidth: 1))
        .clipShape(shape)
        .shadow(color: skin.color(.palette("black", skin.opacity.o50)), radius: skin.size.s30, x: -skin.size.s20)
    }
}
