// kit-candidate: controls the prototype's operations screens share and the kit lacks — a card radio grid
// (`dl-at` / `aa-prov`, spec 06 K4), the click-to-edit mono value pill (`.val`), a toggle chip (`.ac-trig`), and the
// small segment (`.cs-th`).
import AinkradAppKit
import SwiftUI

/// One card of a `ChoiceCardGrid`.
struct ChoiceCard<ID: Hashable>: Identifiable {
    let id: ID
    var title: String
    var detail: String
    /// An SF Symbol in the blue icon tile, or a custom leading view.
    var systemImage: String?
    var leading: AnyView?
    /// The selected wash and rim; blue when nil.
    var tint: Color?
    var isEnabled = true
    var help: String?
}

/// A grid of selectable cards: `isOn` marks the chosen ones (one or many), `pick` answers a tap.
struct ChoiceCardGrid<ID: Hashable>: View {
    let cards: [ChoiceCard<ID>]
    var columns = 3
    /// Centred cards (provider tiles) instead of leading-aligned ones.
    var centered = false
    let isOn: (ID) -> Bool
    let pick: (ID) -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: skin.size.s8), count: columns),
            spacing: skin.size.s8
        ) {
            ForEach(cards) { card in
                ChoiceCardView(card: card, centered: centered, isOn: isOn(card.id)) { pick(card.id) }
            }
        }
    }
}

private struct ChoiceCardView<ID: Hashable>: View {
    let card: ChoiceCard<ID>
    let centered: Bool
    let isOn: Bool
    let pick: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let tint = card.tint ?? skin.color(skin.palette.accentPrimary)
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        AinkradTapArea(help: card.help, action: { if card.isEnabled { pick() } }) {
            VStack(alignment: centered ? .center : .leading, spacing: skin.size.s6) {
                if let leading = card.leading {
                    leading
                } else if let image = card.systemImage {
                    Image(systemName: image).citadelFont("t13", weight: "medium")
                        .foregroundStyle(skin.color(skin.palette.accentPrimary))
                        .frame(width: skin.size.s30, height: skin.size.s30)
                        .background(
                            skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o14),
                            in: RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous))
                }
                Text(card.title).citadelFont("t12_5", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.primary))
                if !card.detail.isEmpty {
                    Text(card.detail).citadelFont(centered ? "t10_5" : "t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                        .multilineTextAlignment(centered ? .center : .leading)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .padding(centered ? skin.size.s14 : skin.size.s12)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: centered ? .top : .topLeading)
            .background(
                shape.fill(isOn ? tint.opacity(skin.opacity.o12) : skin.color(.palette("black", skin.opacity.o18)))
            )
            .overlay(
                shape.strokeBorder(
                    isOn ? tint.opacity(skin.opacity.o55) : skin.color(.palette("foreground", skin.opacity.o06)),
                    lineWidth: 1)
            )
            .shadow(color: isOn ? tint.opacity(skin.opacity.o15) : .clear, radius: skin.size.s12, y: skin.size.s8)
            .contentShape(shape)
        }
        .opacity(card.isEnabled ? 1 : skin.opacity.o45)
        .offset(y: hovering && card.isEnabled && !reduceMotion ? -skin.size.s2 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .animation(skin.animation(skin.motion.hover), value: isOn)
    }
}

/// `.val`: a mono value pill; a click turns it into a field, Return commits (the caller checks and refuses).
struct InlineValuePill: View {
    let text: String
    var help: String?
    var tint: Color?
    let commit: (String) -> Void
    @State private var editing = false
    @State private var draft = ""
    @FocusState private var focused: Bool
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        if editing {
            AinkradTextField(text: $draft, placeholder: text, focus: $focused)
                .monospaced().compact()
                .onReturn { _ in
                    editing = false
                    commit(draft)
                }
                .frame(width: skin.size.s90)
                .onAppear {
                    draft = text
                    focused = true
                }
                .onChange(of: focused) { _, now in if !now { editing = false } }
        } else {
            AinkradTapArea(help: help, action: { editing = true }) {
                Text(text).citadelFont("t11", mono: true)
                    .foregroundStyle(tint ?? skin.color(skin.text.muted))
                    .padding(.horizontal, skin.size.s6)
                    .padding(.vertical, skin.size.s1)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o06)),
                        in: RoundedRectangle(cornerRadius: skin.size.s5, style: .continuous)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: skin.size.s5, style: .continuous)
                            .strokeBorder(skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
            }
        }
    }
}

/// `.scope`: where a value comes from — "↳ server" (faint), or "● project ↺" (cyan) with a reset.
struct ScopeChip: View {
    let text: String
    var overridden = false
    var reset: (() -> Void)?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let tint = overridden ? theme.accentSecondary : skin.color(skin.text.faint)
        HStack(spacing: skin.size.s4) {
            Text(overridden ? "● \(text)" : "↳ \(text)")
            if let reset {
                AinkradTapArea(help: "Reset to inherited", action: reset) { Text("↺") }
            }
        }
        .citadelFont("t10_5", mono: true)
        .foregroundStyle(tint)
        .padding(.horizontal, skin.size.s6)
        .padding(.vertical, skin.size.s1)
        .background(
            (overridden ? tint.opacity(skin.opacity.o12) : skin.color(.palette("foreground", skin.opacity.o05))),
            in: RoundedRectangle(cornerRadius: skin.size.s5, style: .continuous))
    }
}

/// `.ac-trig span`: a toggle chip — "✓ rate-limited" on (cyan), "○ refused task" off.
struct ToggleChip: View {
    let title: String
    let isOn: Bool
    var isEnabled = true
    var help: String?
    let toggle: () -> Void
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let cyan = theme.accentSecondary
        let shape = RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous)
        AinkradTapArea(help: help, action: { if isEnabled { toggle() } }) {
            Text("\(isOn ? "✓" : "○") \(title)").citadelFont("t11")
                .foregroundStyle(isOn ? cyan : skin.color(skin.text.faint))
                .padding(.horizontal, skin.size.s10)
                .frame(height: skin.size.s28)
                .background(
                    shape.fill(
                        isOn ? cyan.opacity(skin.opacity.o10) : skin.color(.palette("foreground", skin.opacity.o05)))
                )
                .overlay(
                    shape.strokeBorder(
                        isOn ? cyan.opacity(skin.opacity.o35) : skin.color(.palette("foreground", skin.opacity.o07)),
                        lineWidth: 1))
        }
        .opacity(isEnabled ? 1 : skin.opacity.o45)
        .animation(skin.animation(skin.motion.hover), value: isOn)
    }
}

/// `.cs-th`: a small segment of plain options, the chosen one blue-washed with an inset ring.
struct MiniSegment<ID: Hashable>: View {
    let options: [(id: ID, title: String)]
    @Binding var selection: ID
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s6) {
            ForEach(options, id: \.id) { option in
                let isOn = option.id == selection
                let shape = RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous)
                AinkradTapArea(action: { selection = option.id }) {
                    Text(option.title).citadelFont("t11")
                        .foregroundStyle(isOn ? skin.color(.palette("foreground", 1)) : skin.color(skin.text.muted))
                        .padding(.horizontal, skin.size.s10)
                        .frame(height: skin.size.s26)
                        .background(
                            shape.fill(
                                isOn
                                    ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o22)
                                    : skin.color(.palette("foreground", skin.opacity.o05)))
                        )
                        .overlay(
                            shape.strokeBorder(
                                isOn ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o40) : .clear,
                                lineWidth: 1))
                }
            }
        }
        .animation(skin.animation(skin.motion.hover), value: selection)
    }
}
