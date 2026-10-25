import AinkradAppKit
import SwiftUI

/// The company's chain presets as option tiles, for the places that pick one before an agent exists (the hire
/// wizard, the New company wizard's CEO). `selection` nil means the company default (or no preset when it has
/// none); the picked tile shows the chain it is.
struct ChainPresetPicker: View {
    let presets: [ChainPresetInfo]
    @Binding var selection: Int64?
    @Environment(\.ainkradSkin) private var skin

    private var shown: Int64? { selection ?? presets.first(where: \.isDefault)?.id }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s8) {
            AinkradOptionGrid(
                options: presets.map { preset in
                    let tint = ChainPresetStyle.tint(preset, skin: skin)
                    return AinkradOption(
                        id: preset.id, title: preset.name + (preset.isDefault ? " · default" : ""),
                        detail: preset.entries.isEmpty ? "its own model only" : preset.detail,
                        leading: AnyView(
                            LetterTile(letter: String(preset.name.prefix(1)), tint: tint, size: skin.size.s32)),
                        tint: tint)
                }, columns: 2, isOn: { $0 == shown }
            ) { picked in
                selection = presets.first { $0.id == picked }?.isDefault == true ? nil : picked
            }
            if let preset = presets.first(where: { $0.id == shown }), !preset.entries.isEmpty {
                HStack(spacing: skin.size.s6) {
                    Text("its own model, then").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    AinkradChainFlow(steps: preset.entries.map { ($0.harness, $0.model) }) {
                        HarnessTag(harness: $0, size: skin.size.s20)
                    }
                }
            }
        }
    }
}
