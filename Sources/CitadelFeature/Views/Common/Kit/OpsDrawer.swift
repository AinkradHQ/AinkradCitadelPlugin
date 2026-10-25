// kit-candidate: the prototype's floating inset drawer (`opsOpen` / `.ak-drawer`) — a scrim over the pane, an inset
// panel on the trailing edge with a crumb header, a scrolling body and an optional footer; Esc or the scrim closes.
// `.ainkradDrawer` is full-height and chamfered with no crumb or footer (spec 06 K3). Self-contained so it can move.
import AinkradAppKit
import SwiftUI

extension View {
    /// Hosts an `OpsDrawerPanel` over this view while `isPresented`: scrim, inset trailing panel, slide-in.
    func opsDrawer<Panel: View>(isPresented: Binding<Bool>, @ViewBuilder panel: @escaping () -> Panel) -> some View {
        modifier(OpsDrawerHost(isPresented: isPresented, panel: panel))
    }
}

private struct OpsDrawerHost<Panel: View>: ViewModifier {
    @Binding var isPresented: Bool
    let panel: () -> Panel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    func body(content: Content) -> some View {
        content.overlay {
            GeometryReader { geo in
                ZStack(alignment: .trailing) {
                    if isPresented {
                        skin.color(.palette("black", skin.opacity.o35))
                            .contentShape(Rectangle())
                            .onTapGesture { isPresented = false }
                            .transition(.opacity)
                        panel()
                            .frame(width: min(skin.size.s380 * 2, geo.size.width * 0.62))
                            .padding(.top, skin.size.s56)
                            .padding(.trailing, skin.size.s34)
                            .padding(.bottom, skin.size.s34)
                            .transition(.move(edge: .trailing).combined(with: .opacity))
                        AinkradTapArea(action: { isPresented = false }) { EmptyView() }
                            .keyboardShortcut(.cancelAction)
                            .frame(width: 0, height: 0)
                            .opacity(0)
                    }
                }
                .frame(width: geo.size.width, height: geo.size.height, alignment: .trailing)
            }
            .animation(
                reduceMotion
                    ? nil : skin.animation(AinkradAnimationToken(curve: "spring", response: 0.35, damping: 0.86)),
                value: isPresented)
        }
    }
}

/// The drawer itself: "Section › **Title**" with ✕, a scrolling body, and a footer when one is given.
struct OpsDrawerPanel<Content: View, Foot: View>: View {
    let crumb: [String]
    let close: () -> Void
    @ViewBuilder let content: Content
    @ViewBuilder let footer: Foot
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: skin.size.s8) {
                crumbText.lineLimit(1)
                Spacer(minLength: skin.size.s8)
                AinkradTapArea(help: "Close (Esc)", action: close) {
                    Image(systemName: "xmark").citadelFont("t12", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.muted))
                        .frame(width: skin.size.s30, height: skin.size.s30)
                        .contentShape(Rectangle())
                }
            }
            .padding(.horizontal, skin.size.s16)
            .padding(.vertical, skin.size.s10)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s12) { content }
                    .padding(.horizontal, skin.size.s16)
                    .padding(.bottom, skin.size.s16)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .scrollIndicators(.never)
            if Foot.self != EmptyView.self {
                HStack(spacing: skin.size.s8) { footer }
                    .padding(.horizontal, skin.size.s16)
                    .padding(.vertical, skin.size.s12)
                    .frame(maxWidth: .infinity)
                    .background(skin.color(.palette("foreground", skin.opacity.o03)))
            }
        }
        .background(shape.fill(skin.color(.palette("background", skin.opacity.o97))))
        .clipShape(shape)
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
        .shadow(color: skin.color(.palette("black", skin.opacity.o50)), radius: skin.size.s30, x: -skin.size.s20)
    }

    private var crumbText: Text {
        var text = Text("")
        for (index, part) in crumb.enumerated() {
            let last = index == crumb.count - 1
            if index > 0 { text = text + Text("  ›  ").foregroundStyle(skin.color(skin.text.faint)) }
            text =
                text
                + (last
                    ? Text(part).bold().foregroundStyle(skin.color(skin.text.primary))
                    : Text(part).foregroundStyle(skin.color(skin.text.faint)))
        }
        return text.font(skin.font(AinkradFontToken(sizeKey: "t12", mono: "family")))
    }
}

extension OpsDrawerPanel where Foot == EmptyView {
    init(crumb: [String], close: @escaping () -> Void, @ViewBuilder content: () -> Content) {
        self.init(crumb: crumb, close: close, content: content, footer: { EmptyView() })
    }
}

/// `dr-hero`: a tinted card with a radial glow, a leading tile, a mono title and subtitle, and a trailing accessory.
struct OpsDrawerHero<Leading: View, Trailing: View>: View {
    let tint: Color
    let title: String
    let subtitle: String
    @ViewBuilder let leading: Leading
    @ViewBuilder let trailing: Trailing
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        HStack(spacing: skin.size.s14) {
            leading
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text(title).citadelFont("t16", weight: "bold", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                Text(subtitle).citadelFont("t12").foregroundStyle(skin.color(skin.text.faint)).lineLimit(2)
            }
            Spacer(minLength: skin.size.s8)
            trailing
        }
        .padding(skin.size.s16)
        .background(
            ZStack(alignment: .topLeading) {
                shape.fill(
                    LinearGradient(
                        colors: [tint.opacity(skin.opacity.o16), skin.color(.palette("foreground", skin.opacity.o03))],
                        startPoint: .topLeading, endPoint: .bottomTrailing))
                RadialGradient(
                    colors: [tint.opacity(skin.opacity.o30), .clear], center: .topLeading, startRadius: 0,
                    endRadius: skin.size.s140)
            }
            .clipShape(shape)
        )
        .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o25), lineWidth: 1))
    }
}

/// `dl-sec`: a section card with a bold title and a faint right-hand hint.
struct OpsSection<Content: View, Hint: View>: View {
    let title: String
    @ViewBuilder let hint: Hint
    @ViewBuilder let content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(alignment: .firstTextBaseline, spacing: skin.size.s10) {
                Text(title).citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                Spacer(minLength: skin.size.s8)
                hint.citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            content
        }
        .padding(skin.size.s14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o03))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o05)), lineWidth: 1))
    }
}

extension OpsSection where Hint == Text {
    init(title: String, hint: String = "", @ViewBuilder content: () -> Content) {
        self.init(title: title, hint: { Text(hint) }, content: content)
    }
}

/// `.ops-hint`: faint 11.5 pt explanatory copy.
struct OpsHint: View {
    let text: String
    @Environment(\.ainkradSkin) private var skin

    init(_ text: String) { self.text = text }

    var body: some View {
        Text(text).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            .fixedSize(horizontal: false, vertical: true)
    }
}
