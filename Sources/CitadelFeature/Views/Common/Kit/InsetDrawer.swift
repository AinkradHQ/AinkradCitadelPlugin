// kit-candidate: `.ainkradDrawer` is full-height and chamfered with no crumb or footer (spec 06 K3). The prototype's
// operations drawer (`opsOpen` / `.ak-drawer`): a floating panel inset from the pane, a crumb header, a scrolling body
// and a footer bar, over a light scrim.
import AinkradAppKit
import SwiftUI

extension View {
    /// Shows a floating drawer over this view's trailing side: the crumb ("Runners › hetzner-1 · log") with ✕, the
    /// body scrolling under it, and `foot` as the action bar. The scrim, ✕ and Esc close it.
    func insetDrawer<Body: View, Foot: View>(
        isPresented: Binding<Bool>, crumb: [String], @ViewBuilder content: @escaping () -> Body,
        @ViewBuilder foot: @escaping () -> Foot
    ) -> some View {
        modifier(InsetDrawerModifier(isPresented: isPresented, crumb: crumb, drawer: content, foot: foot))
    }
}

private struct InsetDrawerModifier<Drawer: View, Foot: View>: ViewModifier {
    @Binding var isPresented: Bool
    let crumb: [String]
    let drawer: () -> Drawer
    let foot: () -> Foot
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                ZStack(alignment: .topTrailing) {
                    if isPresented {
                        skin.color(.palette("background", 1)).opacity(skin.opacity.o35)
                            .contentShape(Rectangle())
                            .onTapGesture { close() }
                            .transition(.opacity)
                        panel
                            .frame(width: min(skin.size.s640 + skin.size.s120, geo.size.width * 0.62))
                            .padding(.top, skin.size.s62)
                            .padding(.trailing, skin.size.s20)
                            .padding(.bottom, skin.size.s20)
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

    private var panel: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        return VStack(spacing: 0) {
            HStack(spacing: skin.size.s6) {
                ForEach(Array(crumb.enumerated()), id: \.offset) { index, part in
                    if index > 0 { Text(verbatim: "›").foregroundStyle(skin.color(skin.text.faint)) }
                    Text(part)
                        .citadelFont(
                            "t12", weight: index == crumb.count - 1 ? "bold" : nil, mono: index == crumb.count - 1
                        )
                        .foregroundStyle(skin.color(index == crumb.count - 1 ? skin.text.primary : skin.text.faint))
                        .lineLimit(1)
                }
                Spacer(minLength: skin.size.s8)
                CloseX { close() }
            }
            .citadelFont("t12")
            .padding(.horizontal, skin.size.s16)
            .padding(.vertical, skin.size.s14)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s12) { drawer() }
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .padding(.horizontal, skin.size.s16)
                    .padding(.bottom, skin.size.s16)
            }
            .scrollIndicators(.never)
            if Foot.self != EmptyView.self {
                HStack(spacing: skin.size.s8) { foot() }
                    .padding(.horizontal, skin.size.s16)
                    .padding(.vertical, skin.size.s12)
                    .frame(maxWidth: .infinity)
                    .background(skin.color(.palette("foreground", skin.opacity.o03)))
            }
        }
        .background(skin.color(.palette("background", 1)).opacity(skin.opacity.o90), in: shape)
        .background(.ultraThinMaterial, in: shape)
        .clipShape(shape)
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
        .shadow(
            color: skin.color(.palette("background", 1)).opacity(skin.opacity.o50), radius: skin.size.s30,
            x: -skin.size.s20
        )
        .onExitCommand { close() }
    }

    private func close() { isPresented = false }
}

/// The drawer's 30 pt ✕.
private struct CloseX: View {
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
        .buttonStyle(.plain)
        .keyboardShortcut(.cancelAction)
        .onHover { hovering = $0 }
    }
}
