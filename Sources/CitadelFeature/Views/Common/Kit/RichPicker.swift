// kit-candidate: K2 — the rich picker (`.rs-pick`: icon tile, caption over value, a chevron that turns, an "on"
// ring) and its menu (`.rs-menu`: a header, rows with a leading view, two lines, trailing extras, a count badge and
// a check, staggered in). `AinkradSelect` / `AinkradGroupedSelect` rows hold only a title and detail.
import AinkradAppKit
import SwiftUI

/// The picker button. Its menu drops from its trailing edge in-window (screens add a tap-away layer under it); the
/// screen puts the bar above the page with `zIndex` so the menu draws over it.
struct RichPicker<Icon: View, Menu: View>: View {
    let caption: String
    let value: String
    let isOn: Bool
    @Binding var isOpen: Bool
    @ViewBuilder let icon: Icon
    @ViewBuilder let menu: Menu
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        let tile = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        let accent = skin.color(skin.palette.accentPrimary)
        AinkradTapArea(action: { isOpen.toggle() }) {
            HStack(spacing: skin.size.s10) {
                icon
                    .foregroundStyle(skin.color(isOn ? .palette("foreground", 1) : skin.text.muted))
                    .frame(width: skin.size.s40, height: skin.size.s40)
                    .background {
                        if isOn {
                            tile.fill(
                                LinearGradient(
                                    colors: [
                                        accent.opacity(skin.opacity.o30),
                                        skin.color(skin.palette.accentViolet).opacity(skin.opacity.o25),
                                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
                        } else {
                            tile.fill(
                                skin.color(.palette("foreground", hovering ? skin.opacity.o09 : skin.opacity.o05)))
                        }
                    }
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    Text(skin.labelCased(caption).uppercased()).citadelFont("t10").tracking(skin.size.s1 / 2)
                        .foregroundStyle(skin.color(skin.text.faint))
                    Text(value).citadelFont("t12_5", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                        .lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                Image(systemName: "chevron.down").citadelFont("t11", weight: "semibold")
                    .foregroundStyle(skin.color(isOpen ? skin.text.primary : skin.text.faint))
                    .rotationEffect(.degrees(isOpen ? 180 : 0))
            }
            .padding(.leading, skin.size.s6)
            .padding(.trailing, skin.size.s12)
            .padding(.vertical, skin.size.s5)
            .frame(minWidth: skin.size.s168, minHeight: skin.size.s52)
            .background(
                shape.fill(
                    skin.color(.palette("background", hovering ? skin.opacity.o80 : skin.opacity.o72)))
            )
            .overlay(
                shape.strokeBorder(
                    isOn || isOpen
                        ? accent.opacity(skin.opacity.o35) : skin.color(.palette("foreground", skin.opacity.o07)),
                    lineWidth: 1)
            )
            .background(
                shape.stroke(accent.opacity(isOn || isOpen ? skin.opacity.o12 : 0), lineWidth: skin.size.s3)
            )
            .contentShape(shape)
        }
        .fixedSize()
        .offset(y: hovering && !reduceMotion ? -skin.size.s1 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(AinkradAnimationToken(curve: "spring", response: 0.3, damping: 0.7)), value: isOpen)
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .overlay(alignment: .topTrailing) {
            if isOpen {
                menu
                    .offset(y: skin.size.s52 + skin.size.s6)
                    .transition(
                        reduceMotion
                            ? .opacity
                            : .scale(scale: 0.94, anchor: .topTrailing).combined(with: .opacity))
            }
        }
    }
}

/// The menu's panel: a header label and its rows, scrolling past 460.
struct RichMenu<Content: View>: View {
    let header: String
    @ViewBuilder let content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        ScrollView {
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(header).citadelFont("t11", weight: "semibold").foregroundStyle(skin.color(skin.text.faint))
                    .padding(.horizontal, skin.size.s10)
                    .padding(.top, skin.size.s6)
                    .padding(.bottom, skin.size.s4)
                content
            }
            .padding(skin.size.s6)
        }
        .scrollBounceBehavior(.basedOnSize)
        .frame(width: skin.size.s340)
        .frame(maxHeight: skin.size.s460)
        .fixedSize(horizontal: false, vertical: true)
        .background(shape.fill(skin.color(.palette("surface", skin.opacity.o96))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o10)), lineWidth: 1))
        .clipShape(shape)
        .shadow(color: skin.color(.palette("black", skin.opacity.o50)), radius: skin.size.s30, y: skin.size.s24)
    }
}

/// A divider between the "Everyone" row and the rest.
struct RichMenuSeparator: View {
    @Environment(\.ainkradSkin) private var skin
    var body: some View {
        Rectangle().fill(skin.color(.palette("foreground", skin.opacity.o07))).frame(height: skin.size.s1)
            .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s4)
    }
}

/// One menu row: leading view, a bold title over a faint line, extras, the count badge, the check.
struct RichMenuRow<Leading: View, Extra: View>: View {
    let title: String
    let subtitle: String
    var count: Int?
    var isChecked = false
    var index = 0
    let action: () -> Void
    @ViewBuilder let leading: Leading
    @ViewBuilder let extra: Extra
    @State private var hovering = false
    @State private var shown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s11, style: .continuous)
        AinkradTapArea(action: action) {
            HStack(spacing: skin.size.s10) {
                leading
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    Text(title).citadelFont("t12_5", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                    Text(subtitle).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                extra
                if let count {
                    Text("\(count)").citadelFont("t10_5", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.muted))
                        .padding(.horizontal, skin.size.s6)
                        .frame(minWidth: skin.size.s24, minHeight: skin.size.s20)
                        .background(
                            skin.color(.palette("foreground", skin.opacity.o07)),
                            in: RoundedRectangle(cornerRadius: skin.size.s6))
                }
                Image(systemName: "checkmark").citadelFont("t11", weight: "bold")
                    .foregroundStyle(skin.color(skin.palette.accentSecondary))
                    .frame(width: skin.size.s18)
                    .opacity(isChecked ? 1 : 0)
            }
            .padding(.horizontal, skin.size.s8)
            .padding(.vertical, skin.size.s6)
            .background {
                if hovering {
                    shape.fill(
                        LinearGradient(
                            colors: [
                                skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o22),
                                skin.color(skin.palette.accentViolet).opacity(skin.opacity.o12),
                            ], startPoint: .leading, endPoint: .trailing))
                }
            }
            .contentShape(shape)
        }
        .offset(x: reduceMotion ? 0 : (shown ? (hovering ? skin.size.s2 : 0) : skin.size.s10))
        .opacity(shown || reduceMotion ? 1 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .onAppear {
            withAnimation(
                skin.animation(AinkradAnimationToken(curve: "spring", response: 0.3, damping: 0.8))
                    .delay(Double(index) * 0.026)
            ) { shown = true }
        }
    }
}

extension RichMenuRow where Extra == EmptyView {
    init(
        title: String, subtitle: String, count: Int? = nil, isChecked: Bool = false, index: Int = 0,
        action: @escaping () -> Void, @ViewBuilder leading: () -> Leading
    ) {
        self.init(
            title: title, subtitle: subtitle, count: count, isChecked: isChecked, index: index, action: action,
            leading: leading, extra: { EmptyView() })
    }
}
