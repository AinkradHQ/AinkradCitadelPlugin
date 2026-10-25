import AinkradAppKit
import SwiftUI

/// The prototype's literal hues, mapped onto skin tokens (and two named figure palettes where the skin has none).
enum Hue {
    case blue, violet, green, cyan, pink, amber, slate, red, yellow

    func color(_ skin: AinkradSkin) -> Color {
        switch self {
        case .blue: skin.color(skin.palette.accentPrimary)
        case .violet: skin.color(skin.palette.accentViolet)
        case .green: skin.color(skin.palette.success)
        case .cyan: skin.color(skin.palette.accentSecondary)
        case .pink: AinkradFigurePalette.sakura.deepColor
        case .amber: AinkradFigurePalette.ember.lightColor
        case .slate: skin.color(skin.text.muted)
        case .red: skin.color(skin.palette.danger)
        case .yellow: skin.color(skin.palette.warning)
        }
    }

    init(_ tool: ToolLook.Hue) {
        switch tool {
        case .blue: self = .blue
        case .violet: self = .violet
        case .green: self = .green
        case .cyan: self = .cyan
        case .pink: self = .pink
        case .slate: self = .slate
        }
    }

    init(_ tone: RunLook.Tone) {
        switch tone {
        case .run: self = .cyan
        case .ok: self = .green
        case .warn: self = .yellow
        case .err: self = .red
        case .idle: self = .slate
        }
    }
}
