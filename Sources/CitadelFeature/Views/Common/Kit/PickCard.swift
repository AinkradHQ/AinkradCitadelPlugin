// kit-candidate: the prototype's choice card (`.h-card`, spec 05 §8 / §10.7): a selectable card for single, multi
// and toggle choices, a dashed "add" variant and the blue on-state; plus its check box, the toggle-row (`.h-guide`)
// and a fixed-column grid. The kit has no card-shaped picker (AinkradSegmentedPicker is a pill strip).
import AinkradAppKit
import SwiftUI

struct PickCard<Content: View>: View {
    var isOn = false
    var isAdd = false
    var minHeight: CGFloat?
    var vertical = false
    var action: (() -> Void)?
    @ViewBuilder let content: Content
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        let blue = skin.color(skin.palette.accentPrimary)
        let fg = skin.color(.palette("foreground", 1))
        let fill: Color =
            isOn
            ? blue.opacity(skin.opacity.o14)
            : isAdd
                ? (hovering ? blue.opacity(skin.opacity.o06) : .clear)
                : fg.opacity(hovering ? skin.opacity.o07 : skin.opacity.o05)
        let rim: Color =
            isOn
            ? blue.opacity(skin.opacity.o50)
            : isAdd && hovering
                ? blue.opacity(skin.opacity.o45) : fg.opacity(hovering ? skin.opacity.o13 : skin.opacity.o07)
        Group {
            if vertical {
                VStack(alignment: .leading, spacing: skin.size.s3) { content }
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .topLeading)
                    .padding(.vertical, skin.size.s10)
            } else {
                HStack(spacing: skin.size.s10) { content }
                    .frame(maxWidth: .infinity, minHeight: minHeight, alignment: .leading)
            }
        }
        .padding(.horizontal, skin.size.s12)
        .background(shape.fill(fill))
        .overlay(
            shape.strokeBorder(rim, style: StrokeStyle(lineWidth: 1, dash: isAdd ? [skin.size.s4, skin.size.s3] : []))
        )
        .contentShape(shape)
        .onHover { hovering = action != nil && $0 }
        .onTapGesture { action?() }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: hovering)
        .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: isOn)
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isOn ? [.isButton, .isSelected] : .isButton)
    }
}

/// A pick card's title over its faint caption.
struct PickText: View {
    let title: String
    var caption: String?
    var mono = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s2) {
            Text(title).citadelFont("t12_5", weight: "semibold", mono: mono).foregroundStyle(
                skin.color(skin.text.primary)
            )
            .lineLimit(1)
            if let caption {
                Text(caption).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The 18 pt check box (`.h-check`).
struct PickCheck: View {
    let isOn: Bool
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s5, style: .continuous)
        Image(systemName: "checkmark").citadelFont("t10", weight: "bold")
            .foregroundStyle(skin.color(.palette("foreground", 1))).opacity(isOn ? 1 : 0)
            .frame(width: skin.size.s18, height: skin.size.s18)
            .background(shape.fill(isOn ? skin.color(skin.palette.accentPrimary) : .clear))
            .overlay(
                shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o25)), lineWidth: 1).opacity(
                    isOn ? 0 : 1))
    }
}

/// The 28 pt glyph tile at a card's left (`.h-ic`).
struct PickGlyph: View {
    let glyph: String
    var symbol = false
    var isOn = false
    var tint: Color?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let blue = tint ?? skin.color(skin.palette.accentPrimary)
        Group {
            if symbol { Image(systemName: glyph) } else { Text(glyph) }
        }
        .citadelFont("t13", weight: "semibold")
        .foregroundStyle(isOn ? skin.color(.palette("foreground", 1)) : blue)
        .frame(width: skin.size.s28, height: skin.size.s28)
        .background(
            isOn ? blue.opacity(skin.opacity.o30) : skin.color(.palette("foreground", skin.opacity.o06)),
            in: RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous))
    }
}

/// A toggle row (`.h-guide`): check, text, and the kit switch; the whole card toggles.
struct ToggleCard: View {
    let title: String
    let isOn: Bool
    var glyph: String?
    var flash = false
    let toggle: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        PickCard(isOn: isOn, minHeight: skin.size.s46, action: toggle) {
            if let glyph { PickGlyph(glyph: glyph, isOn: isOn).scaleEffect(0.86) } else { PickCheck(isOn: isOn) }
            Text(title).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
            AinkradToggle(isOn: Binding(get: { isOn }, set: { _ in toggle() })).fixedSize()
        }
        .background(
            RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
                .fill(skin.color(skin.palette.success).opacity(flash ? skin.opacity.o25 : 0)))
    }
}

/// A fixed-column grid of equal cards (`.h-grid2/3/4`).
struct PickGrid<Content: View>: View {
    let columns: Int
    var spacing: CGFloat?
    @ViewBuilder let content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        LazyVGrid(
            columns: Array(
                repeating: GridItem(.flexible(), spacing: spacing ?? skin.size.s8, alignment: .top), count: columns),
            alignment: .leading, spacing: spacing ?? skin.size.s8
        ) { content }
    }
}
