// kit-candidate: K9 — `AinkradDockButton` with any icon view (an agent figure) and the cyan "on" state of a toggle
// (`.dk.on`: Follow live, the Grid / List switch). The kit button takes an SF symbol only and has no on state.
import AinkradAppKit
import SwiftUI

struct DockToggle<Icon: View>: View {
    let title: String
    var isOn = false
    /// The on state's tint: cyan (Follow live) or the accent (Grid / List).
    var onTint: Color?
    var isEnabled = true
    var help: String?
    let action: () -> Void
    @ViewBuilder let icon: Icon
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        let tint = onTint ?? skin.color(skin.palette.accentSecondary)
        AinkradTapArea(help: help, action: action) {
            HStack(spacing: skin.size.s6) {
                icon.frame(width: skin.size.s16, height: skin.size.s16)
                Text(title).citadelFont("t12", weight: "medium")
            }
            .foregroundStyle(isOn ? tint : skin.color(skin.text.primary))
            .padding(.leading, skin.size.s9)
            .padding(.trailing, skin.size.s12)
            .frame(height: skin.size.s34)
            .background(
                shape.fill(
                    isOn
                        ? tint.opacity(skin.opacity.o14)
                        : skin.color(.palette("foreground", hovering ? skin.opacity.o13 : skin.opacity.o07)))
            )
            .overlay(
                shape.strokeBorder(
                    isOn ? tint.opacity(skin.opacity.o35) : skin.color(.palette("foreground", skin.opacity.o09)),
                    lineWidth: 1)
            )
            .contentShape(shape)
        }
        .offset(y: hovering && isEnabled && !reduceMotion ? -skin.size.s2 : 0)
        .opacity(isEnabled ? 1 : skin.opacity.o45)
        .disabled(!isEnabled)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .animation(skin.animation(skin.motion.hover), value: isOn)
    }
}

extension DockToggle where Icon == DockSymbol {
    init(
        _ title: String, systemImage: String, isOn: Bool = false, onTint: Color? = nil, isEnabled: Bool = true,
        help: String? = nil, action: @escaping () -> Void
    ) {
        self.init(
            title: title, isOn: isOn, onTint: onTint, isEnabled: isEnabled, help: help, action: action,
            icon: { DockSymbol(name: systemImage) })
    }
}

struct DockSymbol: View {
    let name: String
    var body: some View { Image(systemName: name).citadelFont("t14", weight: "medium") }
}
