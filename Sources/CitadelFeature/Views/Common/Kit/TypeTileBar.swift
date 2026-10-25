// kit-candidate: K10 — an n-up filter bar of tiles (icon tile + mono count over a label) on one glass track; the
// selected tile washes in its colour with a solid, glowing icon; empty tiles dim. No kit control has a count slot.
import AinkradAppKit
import SwiftUI

struct TypeTile: Identifiable {
    let id: String
    let label: String
    let icon: String
    let count: Int
    let tint: Color
}

struct TypeTileBar: View {
    let tiles: [TypeTile]
    let selection: String
    let select: (String) -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let track = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        HStack(spacing: skin.size.s4) {
            ForEach(tiles) { tile in
                TypeTileView(tile: tile, isOn: tile.id == selection) { select(tile.id) }
            }
        }
        .padding(skin.size.s5)
        .background(track.fill(skin.color(.palette("background", skin.opacity.o72))))
        .overlay(track.strokeBorder(skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
    }
}

private struct TypeTileView: View {
    let tile: TypeTile
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        AinkradTapArea(action: action) {
            HStack(spacing: skin.size.s8) {
                IconTile(
                    systemName: tile.icon, tint: tile.tint, size: skin.size.s28, radius: skin.size.s8, filled: isOn
                )
                .scaleEffect(hovering && !reduceMotion ? 1.08 : 1)
                .rotationEffect(.degrees(hovering && !reduceMotion ? -4 : 0))
                VStack(alignment: .leading, spacing: 0) {
                    Text("\(tile.count)").citadelFont("t13", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary))
                    Text(tile.label).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(.horizontal, skin.size.s8)
            .frame(maxWidth: .infinity)
            .frame(height: skin.size.s40)
            .background {
                if isOn {
                    shape.fill(tile.tint.opacity(skin.opacity.o16))
                        .overlay(shape.strokeBorder(tile.tint.opacity(skin.opacity.o40), lineWidth: 1))
                } else if hovering {
                    shape.fill(skin.color(.palette("foreground", skin.opacity.o05)))
                }
            }
            .contentShape(shape)
        }
        .opacity(tile.count == 0 && !isOn ? skin.opacity.o45 : 1)
        .onHover { hovering = $0 }
        .animation(skin.animation(AinkradAnimationToken(curve: "spring", response: 0.3, damping: 0.6)), value: hovering)
        .animation(skin.animation(skin.motion.hover), value: isOn)
    }
}
