// kit-candidate: AinkradInfoTile (spec 02 K6) — the prototype's `.rsd-cx` context tile (tinted icon square, faint
// label, value), laid out two to a row by `InfoTileGrid`. Generic: no Citadel types.
import AinkradAppKit
import SwiftUI

/// An icon square tinted `tint`, a faint label over a value.
struct InfoTile: View {
    let systemImage: String
    let tint: Color
    let label: String
    let value: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s10) {
            Image(systemName: systemImage)
                .citadelFont("t14", weight: "medium")
                .foregroundStyle(tint)
                .frame(width: skin.size.s32, height: skin.size.s32)
                .background(tint.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s10))
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(label).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                Text(value).citadelFont("t12_5", weight: "medium").foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s10)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)), in: RoundedRectangle(cornerRadius: skin.size.s14))
    }
}

/// Info tiles two to a row (`.rsd-ctx`).
struct InfoTileGrid: View {
    let tiles: [InfoTile]
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        LazyVGrid(
            columns: [GridItem(.flexible(), spacing: skin.size.s8), GridItem(.flexible(), spacing: skin.size.s8)],
            spacing: skin.size.s8
        ) {
            ForEach(Array(tiles.enumerated()), id: \.offset) { _, tile in tile }
        }
    }
}
