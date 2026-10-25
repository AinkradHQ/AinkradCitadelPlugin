// kit-candidate: the fallback-chain editor (`.ac-chain`, spec 06 K9) — a vertical rail behind numbered discs (the
// serving one in a cyan→blue gradient), grip rows that drag to reorder and lift while dragged, ✕ to remove — and the
// compact read-only chain flow (`.pr-flow`). `AinkradReorderList` has neither the rail nor the disc styling.
import AinkradAppKit
import SwiftUI
import UniformTypeIdentifiers

/// One entry of a chain as drawn.
struct ChainLink: Identifiable, Equatable {
    let id: String
    var harness: String
    var model: String
    /// The account line under the model ("pool", "opencode-local · unpriced").
    var detail: String
    var detailWarns = false
    /// "serving" / "first".
    var chip: String?
    var isCurrent = false
    /// Neither moved nor removed (the agent's own entry).
    var isFixed = false
}

struct ChainEditor: View {
    let links: [ChainLink]
    var editable = true
    var reorder: ([ChainLink]) -> Void = { _ in }
    var remove: (ChainLink) -> Void = { _ in }
    @State private var order: [ChainLink]?
    @State private var dragging: String?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var shown: [ChainLink] { order ?? links }

    var body: some View {
        VStack(spacing: skin.size.s8) {
            ForEach(Array(shown.enumerated()), id: \.element.id) { index, link in
                row(link, number: index + 1)
                    .onDrag {
                        guard editable, !link.isFixed else { return NSItemProvider() }
                        dragging = link.id
                        order = links
                        return NSItemProvider(object: link.id as NSString)
                    }
                    .onDrop(
                        of: [UTType.text],
                        delegate: ChainDrop(
                            target: link, order: $order, dragging: $dragging, links: links, commit: reorder))
            }
        }
        .background(alignment: .topLeading) {
            LinearGradient(
                colors: [theme.accentSecondary, skin.color(.palette("foreground", skin.opacity.o08))],
                startPoint: .top, endPoint: .bottom
            )
            .frame(width: skin.size.s2)
            .padding(.vertical, skin.size.s20)
            .padding(.leading, editable ? skin.size.s46 : skin.size.s22)
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: shown.map(\.id))
        .onChange(of: links) { _, _ in order = nil }
    }

    private func row(_ link: ChainLink, number: Int) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        let cyan = theme.accentSecondary
        let isDragging = dragging == link.id
        return HStack(spacing: skin.size.s10) {
            if editable {
                Text("⋮⋮").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    .frame(width: skin.size.s14).opacity(link.isFixed ? 0 : 1)
            }
            Text("\(number)").citadelFont("t11", weight: "bold", mono: true)
                .foregroundStyle(skin.color(.palette("foreground", 1)))
                .frame(width: skin.size.s26, height: skin.size.s26)
                .background {
                    if link.isCurrent {
                        Circle().fill(
                            LinearGradient(
                                colors: [cyan, skin.color(skin.palette.accentPrimary)], startPoint: .topLeading,
                                endPoint: .bottomTrailing))
                    } else {
                        Circle().fill(skin.color(.palette("background", 1)).opacity(skin.opacity.o90))
                            .overlay(Circle().fill(skin.color(.palette("foreground", skin.opacity.o12))))
                    }
                }
                .overlay(Circle().strokeBorder(skin.color(.palette("background", 1)), lineWidth: skin.size.s3))
            VStack(alignment: .leading, spacing: skin.size.s2) {
                HStack(spacing: skin.size.s6) {
                    HarnessTag(harness: link.harness, size: skin.size.s20)
                    Text(link.model).citadelFont("t12_5", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                    if let chip = link.chip { StatePill(text: chip, tint: cyan) }
                }
                Text(link.detail).citadelFont("t10_5")
                    .foregroundStyle(link.detailWarns ? skin.color(skin.palette.warning) : skin.color(skin.text.faint))
                    .lineLimit(1)
            }
            Spacer(minLength: skin.size.s4)
            if editable && !link.isFixed && links.count > 1 {
                AinkradTapArea(help: "Remove", action: { remove(link) }) {
                    Image(systemName: "xmark").citadelFont("t10", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.faint))
                        .frame(width: skin.size.s22, height: skin.size.s22)
                        .contentShape(Rectangle())
                }
            }
        }
        .padding(.horizontal, skin.size.s10)
        .padding(.vertical, skin.size.s9)
        .background(
            shape.fill(
                isDragging
                    ? skin.color(.palette("background", skin.opacity.o98))
                    : link.isCurrent
                        ? cyan.opacity(skin.opacity.o07) : skin.color(.palette("foreground", skin.opacity.o05)))
        )
        .overlay(
            shape.strokeBorder(
                link.isCurrent ? cyan.opacity(skin.opacity.o45) : skin.color(.palette("foreground", skin.opacity.o07)),
                lineWidth: 1)
        )
        .shadow(
            color: isDragging ? skin.color(.palette("black", skin.opacity.o45)) : .clear, radius: skin.size.s14,
            y: skin.size.s14)
    }
}

/// Moves the dragged entry as it passes each neighbour; the drop commits the new order.
private struct ChainDrop: DropDelegate {
    let target: ChainLink
    @Binding var order: [ChainLink]?
    @Binding var dragging: String?
    let links: [ChainLink]
    let commit: ([ChainLink]) -> Void

    func dropEntered(info: DropInfo) {
        guard let dragging, dragging != target.id, !target.isFixed, var current = order,
            let from = current.firstIndex(where: { $0.id == dragging }),
            let to = current.firstIndex(where: { $0.id == target.id })
        else { return }
        current.move(fromOffsets: IndexSet(integer: from), toOffset: to > from ? to + 1 : to)
        order = current
    }

    func dropUpdated(info: DropInfo) -> DropProposal? { DropProposal(operation: .move) }

    func performDrop(info: DropInfo) -> Bool {
        if let order, order.map(\.id) != links.map(\.id) { commit(order) }
        dragging = nil
        return true
    }
}

/// `.pr-flow`: a chain read left to right — harness tag + model steps joined by arrows, wrapping.
struct ChainFlow: View {
    let steps: [(harness: String, model: String)]
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradFlowLayout(spacing: skin.size.s4, lineSpacing: skin.size.s6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: skin.size.s4) {
                    if index > 0 {
                        Image(systemName: "arrow.right").citadelFont("t10")
                            .foregroundStyle(skin.color(.palette("foreground", skin.opacity.o30)))
                    }
                    HStack(spacing: skin.size.s6) {
                        HarnessTag(harness: step.harness, size: skin.size.s22)
                        Text(step.model).citadelFont("t11").foregroundStyle(skin.color(skin.text.primary))
                            .lineLimit(1)
                    }
                    .padding(.leading, skin.size.s4)
                    .padding(.trailing, skin.size.s9)
                    .frame(height: skin.size.s30)
                    .background(
                        skin.color(.palette("black", skin.opacity.o20)),
                        in: RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous))
                }
            }
        }
    }
}

/// Overlapping figures with a ring (`.ach-av` / `.pr-av`, spec 06 K10).
struct AvatarStack<Item: Identifiable, Face: View>: View {
    let items: [Item]
    let size: CGFloat
    @ViewBuilder let face: (Item) -> Face
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: -size * 0.32) {
            ForEach(items) { item in
                face(item)
                    .frame(width: size, height: size)
                    .background(Circle().fill(skin.color(.palette("background", 1))).padding(-skin.size.s2))
            }
        }
    }
}
