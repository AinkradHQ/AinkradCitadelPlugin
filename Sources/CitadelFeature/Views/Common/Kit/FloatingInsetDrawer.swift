// kit-candidate: `.ainkradDrawer` is edge-flush and chamfered (spec 05 §2.3 / §10.5). The prototype's `.ak-drawer`:
// a floating panel inset from the pane (top, trailing, bottom), r20, a header slot (a glide tab bar or a label)
// with ✕, a scrolling body, over a light scrim. Scrim, ✕ and Esc close it.
import AinkradAppKit
import SwiftUI

extension View {
    func floatingInsetDrawer<Header: View, Body: View>(
        isPresented: Binding<Bool>, @ViewBuilder header: @escaping () -> Header,
        @ViewBuilder content: @escaping () -> Body
    ) -> some View {
        modifier(FloatingInsetDrawer(isPresented: isPresented, header: header, drawer: content))
    }
}

private struct FloatingInsetDrawer<Header: View, Drawer: View>: ViewModifier {
    @Binding var isPresented: Bool
    let header: () -> Header
    let drawer: () -> Drawer
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    if isPresented {
                        skin.color(.palette("background", 1)).opacity(skin.opacity.o35)
                            .contentShape(Rectangle())
                            .onTapGesture { isPresented = false }
                            .transition(.opacity)
                        panel
                            .frame(width: min(skin.size.s640 + skin.size.s120, geo.size.width * 0.62))
                            .padding(.top, skin.size.s62)
                            .padding(.trailing, skin.size.s20)
                            .padding(.bottom, skin.size.s20)
                            .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: skin.size.s60)))
                    }
                }
                .animation(
                    reduceMotion
                        ? nil : skin.animation(AinkradAnimationToken(curve: "spring", response: 0.35, damping: 0.8)),
                    value: isPresented)
            }
        }
    }

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: skin.size.s12) {
                header().frame(maxWidth: .infinity, alignment: .leading)
                DrawerClose { isPresented = false }
            }
            .padding(.horizontal, skin.size.s16)
            .padding(.vertical, skin.size.s14)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s16) { drawer() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, skin.size.s16)
                    .padding(.bottom, skin.size.s16)
            }
            .scrollIndicators(.never)
        }
        .background(skin.color(.palette("background", 1)).opacity(skin.opacity.o90), in: shape)
        .background(.ultraThinMaterial, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o10)), lineWidth: 1))
        .shadow(color: skin.color(.palette("black", skin.opacity.o50)), radius: skin.size.s30, x: -skin.size.s20)
    }
}

/// The drawer's 30 pt ✕ (Esc).
private struct DrawerClose: View {
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(help: "Close (Esc)", action: action) {
            Text(verbatim: "✕").citadelFont("t12")
                .foregroundStyle(skin.color(hovering ? skin.text.primary : skin.text.faint))
                .frame(width: skin.size.s30, height: skin.size.s30)
                .background(
                    skin.color(.palette("foreground", hovering ? skin.opacity.o08 : 0)),
                    in: RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous))
        }
        .keyboardShortcut(.cancelAction)
        .onHover { hovering = $0 }
    }
}
