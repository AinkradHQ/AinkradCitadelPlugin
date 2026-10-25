// kit-candidate: the prototype's `.sx` sheet (spec 03 §5.1) — a 48 pt gradient tile + title + line, a scrolling
// body and a darker footer strip; and the wizard's step bar (spec 03 K4).
import AinkradAppKit
import SwiftUI

struct SheetFrame<Body: View, Foot: View>: View {
    /// Text in the tile (`CIT`, `E`, `1`), or an SF Symbol when `symbol` is set.
    var tile: String
    var symbol = false
    let title: String
    var line: String?
    var maxHeight: CGFloat?
    @ViewBuilder let content: Body
    @ViewBuilder let foot: Foot
    @State private var contentHeight: CGFloat = 0
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: skin.size.s14) {
                SheetTile(text: tile, symbol: symbol)
                VStack(alignment: .leading, spacing: skin.size.s2) {
                    Text(title).citadelFont("t17", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                    if let line {
                        Text(line).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
            }
            .padding(.bottom, skin.size.s16)
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s16) { content }
                    .padding(.vertical, skin.size.s4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .onGeometryChange(for: CGFloat.self) {
                        $0.size.height
                    } action: {
                        contentHeight = $0
                    }
            }
            .frame(height: min(contentHeight, maxHeight ?? skin.size.s560))
            HStack(spacing: skin.size.s8) { foot }
                .padding(.horizontal, skin.size.s24)
                .padding(.vertical, skin.size.s14)
                .frame(maxWidth: .infinity)
                .background(skin.color(.palette("black", skin.opacity.o18)))
                .padding(.horizontal, -skin.size.s24)
                .padding(.bottom, -skin.size.s22)
                .padding(.top, skin.size.s16)
        }
    }
}

struct SheetTile: View {
    let text: String
    var symbol = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = symbol ? skin.color(skin.palette.accentPrimary) : skin.color(skin.palette.accentViolet)
        Group {
            if symbol {
                Image(systemName: text).citadelFont("t20")
            } else {
                Text(text).citadelFont("t12", weight: "bold", mono: true)
            }
        }
        .foregroundStyle(skin.color(skin.palette.white).opacity(skin.opacity.o90))
        .frame(width: skin.size.s48, height: skin.size.s48)
        .background(
            LinearGradient(
                colors: [tint.opacity(skin.opacity.o40), tint.opacity(skin.opacity.o14)], startPoint: .topLeading,
                endPoint: .bottomTrailing),
            in: RoundedRectangle(cornerRadius: skin.size.s13, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s13, style: .continuous)
                .strokeBorder(skin.color(.palette("foreground", skin.opacity.o12)), lineWidth: 1))
    }
}

/// `① Role & team  ② Details …`: the current step blue, done steps ✓ green; every chip jumps to its step.
struct StepBar: View {
    let steps: [String]
    @Binding var current: Int
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, title in
                StepChip(index: index, title: title, current: current) { current = index }
            }
        }
    }
}

private struct StepChip: View {
    let index: Int
    let title: String
    let current: Int
    let pick: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let on = index == current
        let done = index < current
        let blue = skin.color(skin.palette.accentPrimary)
        let green = skin.color(skin.palette.success)
        AinkradTapArea(action: pick) {
            HStack(spacing: skin.size.s8) {
                Group {
                    if done { Image(systemName: "checkmark") } else { Text("\(index + 1)") }
                }
                .citadelFont("t10_5", weight: "semibold", mono: true)
                .foregroundStyle(on ? skin.color(skin.palette.white) : done ? green : skin.color(skin.text.muted))
                .frame(width: skin.size.s20, height: skin.size.s20)
                .background(
                    on
                        ? blue.opacity(skin.opacity.o50)
                        : done ? green.opacity(skin.opacity.o16) : skin.color(.palette("foreground", skin.opacity.o06)),
                    in: RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous))
                Text(title).citadelFont("t11").lineLimit(1)
                Spacer(minLength: 0)
            }
            .foregroundStyle(
                on
                    ? skin.color(skin.palette.white)
                    : hovering
                        ? skin.color(skin.text.primary)
                        : done
                            ? skin.color(skin.text.muted)
                            : skin.color(skin.text.faint)
            )
            .padding(.horizontal, skin.size.s10)
            .frame(maxWidth: .infinity, minHeight: skin.size.s34, maxHeight: skin.size.s34)
            .background(
                on
                    ? blue.opacity(skin.opacity.o16)
                    : skin.color(.palette("foreground", hovering ? skin.opacity.o06 : skin.opacity.o03)),
                in: RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
    }
}
