// kit-candidate: AinkradChoiceCard (spec 03 K2 / K11) — the prototype's `.h-card`: a selectable card for single,
// multi and toggle choices, a dashed "add" variant, the blue on-state; plus its check box and dot meter.
import AinkradAppKit
import SwiftUI

struct ChoiceCard<Content: View>: View {
    var isOn = false
    var isAdd = false
    var height: CGFloat?
    var axis: Axis = .horizontal
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
            if axis == .horizontal {
                HStack(spacing: skin.size.s10) { content }
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .leading)
            } else {
                VStack(alignment: .leading, spacing: skin.size.s3) { content }
                    .frame(maxWidth: .infinity, minHeight: height, maxHeight: height, alignment: .topLeading)
            }
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, axis == .horizontal ? 0 : skin.size.s10)
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

/// A card's two-line body: bold title, faint one-line caption.
struct CardText: View {
    let title: String
    var caption: String?
    var mono = false
    var wraps = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s1) {
            Text(title).citadelFont("t13", weight: "semibold", mono: mono).foregroundStyle(
                skin.color(skin.text.primary)
            )
            .lineLimit(1)
            if let caption {
                Text(caption).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                    .lineLimit(wraps ? 2 : 1).fixedSize(horizontal: false, vertical: wraps)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// The 28 pt glyph tile at a card's left (`.h-ic`): SF Symbol or text glyph, blue when its card is on.
struct CardGlyph: View {
    let glyph: String
    var isSymbol = true
    var isOn = false
    var size: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let side = size ?? skin.size.s28
        let blue = skin.color(skin.palette.accentPrimary)
        Group {
            if isSymbol { Image(systemName: glyph) } else { Text(glyph) }
        }
        .citadelFont("t12", weight: "semibold")
        .foregroundStyle(isOn ? skin.color(skin.palette.white) : blue)
        .frame(width: side, height: side)
        .background(
            (isOn ? blue.opacity(skin.opacity.o30) : skin.color(.palette("foreground", skin.opacity.o06))),
            in: RoundedRectangle(cornerRadius: side * 0.28, style: .continuous))
    }
}

/// The 18 pt check box of a multi-choice card (`.h-check`).
struct CheckBox: View {
    let isOn: Bool
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s5, style: .continuous)
        Image(systemName: "checkmark").citadelFont("t10", weight: "bold")
            .foregroundStyle(skin.color(skin.palette.white)).opacity(isOn ? 1 : 0)
            .frame(width: skin.size.s18, height: skin.size.s18)
            .background(shape.fill(isOn ? skin.color(skin.palette.accentPrimary) : .clear))
            .overlay(
                shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o25)), lineWidth: 1.5).opacity(
                    isOn ? 0 : 1))
    }
}

/// `Quality ▬▬▬▭`: `value` of `of` 14 × 4 dots.
struct DotMeter: View {
    let value: Int
    var of = 4
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s3) {
            ForEach(0..<of, id: \.self) { index in
                Capsule().fill(
                    index < value
                        ? skin.color(skin.palette.accentPrimary) : skin.color(.palette("foreground", skin.opacity.o10))
                )
                .frame(width: skin.size.s14, height: skin.size.s4)
            }
        }
    }
}

/// Three rising bars, `level` of them lit (effort cards).
struct EffortBars: View {
    let level: Int
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(alignment: .bottom, spacing: skin.size.s3) {
            ForEach(0..<3, id: \.self) { index in
                RoundedRectangle(cornerRadius: skin.size.s2)
                    .fill(
                        index <= level
                            ? skin.color(skin.palette.accentPrimary)
                            : skin.color(.palette("foreground", skin.opacity.o14))
                    )
                    .frame(width: skin.size.s5, height: skin.size.s6 + CGFloat(index) * skin.size.s4)
            }
        }
        .frame(width: skin.size.s24, height: skin.size.s16, alignment: .bottomLeading)
    }
}

/// A label row above a card group: `Role`, `Guidelines · 5 on`.
struct GroupLabel: View {
    let title: String
    var trailing: String?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack {
            Text(title).citadelFont("t10_5", weight: "semibold").foregroundStyle(skin.color(skin.text.muted))
            Spacer(minLength: skin.size.s8)
            if let trailing {
                Text(trailing).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
        }
    }
}

/// A fixed-column grid of equal cards (`.h-grid2/3/4`).
struct CardGrid<Content: View>: View {
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
