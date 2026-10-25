import AinkradAppKit
import SwiftUI

/// A run's harness as the prototype's two-letter tag (Cl, Cx, Oc, Ag) in its colour.
struct HarnessTag: View {
    let harness: String
    var size: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let side = size ?? skin.size.s30
        let tint = AgentLook.harness(harness)?.color ?? skin.color(skin.text.muted)
        Text(Self.letters(harness)).citadelFont(side > skin.size.s28 ? "t12" : "t10", weight: "bold", mono: true)
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(
                tint.opacity(skin.opacity.o16), in: RoundedRectangle(cornerRadius: side * 0.3, style: .continuous))
    }

    static func letters(_ harness: String) -> String {
        switch harness.lowercased() {
        case let h where h.hasPrefix("claude"): "Cl"
        case let h where h.hasPrefix("codex"): "Cx"
        case let h where h.hasPrefix("opencode"): "Oc"
        default: "Ag"
        }
    }
}
