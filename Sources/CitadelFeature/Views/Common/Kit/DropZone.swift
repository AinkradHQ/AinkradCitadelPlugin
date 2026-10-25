// kit-candidate: the kanban / backlog drop zone (spec 05 §10.6): a rounded column or section that takes dragged item
// ids (`.draggable(String)`), washing blue with an accent rim while one hovers over it. The kit only has
// AinkradReorderList (one list, no cross-list drops).
import AinkradAppKit
import SwiftUI

extension View {
    /// Makes this view a drop zone for dragged ids; `drop` gets the first id and says whether it took it.
    func dropZone(radius: CGFloat? = nil, rest: Double? = nil, drop: @escaping (String) -> Bool) -> some View {
        modifier(DropZoneModifier(radius: radius, rest: rest, drop: drop))
    }
}

private struct DropZoneModifier: ViewModifier {
    let radius: CGFloat?
    let rest: Double?
    let drop: (String) -> Bool
    @State private var over = false
    @Environment(\.ainkradSkin) private var skin

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: radius ?? skin.size.s16, style: .continuous)
        let blue = skin.color(skin.palette.accentPrimary)
        content
            .background(
                shape.fill(
                    over ? blue.opacity(skin.opacity.o08) : skin.color(.palette("foreground", rest ?? skin.opacity.o03))
                )
            )
            .overlay(
                shape.strokeBorder(
                    over ? blue.opacity(skin.opacity.o45) : skin.color(.palette("foreground", skin.opacity.o07)))
            )
            .dropDestination(for: String.self) { ids, _ in
                ids.first.map(drop) ?? false
            } isTargeted: {
                over = $0
            }
            .animation(skin.animation(skin.motion.hover), value: over)
    }
}
