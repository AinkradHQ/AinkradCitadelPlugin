import AinkradAppKit
import SwiftUI

/// The hero's big mark: the project's icon, or its uploaded logo (API minor 18). Hovering shows a camera; a click
/// uploads a logo, the context menu changes or removes it. An older server stores none, so the mark is plain.
struct ProjectsLogoMark: View {
    let store: CitadelStore
    let facts: ProjectFacts
    let side: CGFloat
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let mark = ProjectMark(glyph: facts.glyph, tint: facts.tint, side: side, logo: facts.logo)
        if facts.hasTrancheB {
            AinkradTapArea(help: "Upload a logo — PNG, JPEG or WebP up to 2 MB", action: upload) {
                mark.overlay {
                    Image(systemName: "camera.fill").citadelFont("t15")
                        .foregroundStyle(skin.color(.palette("foreground", 1)))
                        .frame(width: side, height: side)
                        .background(
                            skin.color(.palette("black", skin.opacity.o45)),
                            in: RoundedRectangle(cornerRadius: side * 0.29, style: .continuous)
                        )
                        .opacity(hovering ? 1 : 0)
                }
            }
            .onHover { hovering = $0 }
            .animation(skin.animation(skin.motion.hover), value: hovering)
            .ainkradContextMenu(menu)
        } else {
            mark
        }
    }

    private var menu: [AinkradMenuItem] {
        var items = [AinkradMenuItem(title: facts.logo == nil ? "Upload logo…" : "Change logo…", action: upload)]
        if facts.logo != nil {
            items.append(
                AinkradMenuItem(title: "Remove logo", isDestructive: true) { store.removeProjectLogo(facts.project) })
        }
        return items
    }

    private func upload() {
        guard let picked = SettingsLogoFile.choose(for: facts.project.name, store: store) else { return }
        store.setProjectLogo(picked.data, type: picked.type, project: facts.project)
    }
}
