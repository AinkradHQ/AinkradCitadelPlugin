import AinkradAppKit
import SwiftUI

/// `COMPANY ① Identity  CEO ② ③ ④ ⑤  SETUP ⑥ ⑦`: only the current step shows its label, the others reveal it on
/// hover; a done step is a green ✓. Steps jump only once the company has a name.
struct NewCompanyStepBar: View {
    let current: Int
    let unlocked: Bool
    let pick: (Int) -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s6) {
            ForEach(Array(NewCompanyDraft.steps.enumerated()), id: \.offset) { index, step in
                if index == 0 || NewCompanyDraft.steps[index - 1].group != step.group {
                    Text(step.group.uppercased()).citadelFont("t10", weight: "medium").tracking(skin.size.s1)
                        .foregroundStyle(skin.color(skin.text.faint))
                        .padding(.leading, index == 0 ? 0 : skin.size.s8).padding(.trailing, skin.size.s2)
                }
                NewCompanyStepPill(index: index, title: step.title, current: current) {
                    if unlocked { pick(index) }
                }
            }
            Spacer(minLength: 0)
        }
    }
}

private struct NewCompanyStepPill: View {
    let index: Int
    let title: String
    let current: Int
    let pick: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let on = index == current
        let done = index < current
        let blue = skin.color(skin.palette.accentPrimary)
        let green = skin.color(skin.palette.success)
        let shape = Capsule()
        AinkradTapArea(action: pick) {
            HStack(spacing: skin.size.s7) {
                Group {
                    if done { Image(systemName: "checkmark") } else { Text("\(index + 1)") }
                }
                .citadelFont("t10_5", weight: "bold", mono: true)
                .foregroundStyle(skin.color(skin.palette.white))
                .frame(width: skin.size.s20, height: skin.size.s20)
                .background(
                    Circle().fill(
                        on
                            ? AnyShapeStyle(
                                LinearGradient(
                                    colors: [blue, skin.color(skin.palette.accentViolet)], startPoint: .topLeading,
                                    endPoint: .bottomTrailing))
                            : done
                                ? AnyShapeStyle(green)
                                : AnyShapeStyle(skin.color(.palette("foreground", skin.opacity.o13)))
                    ))
                if on || hovering {
                    Text(title).citadelFont("t12", weight: "medium").lineLimit(1).fixedSize()
                        .foregroundStyle(skin.color(on ? skin.text.primary : skin.text.muted))
                        .transition(.opacity.combined(with: .scale(scale: 0.8, anchor: .leading)))
                }
            }
            .padding(.horizontal, skin.size.s5)
            .frame(minHeight: skin.size.s30)
            .background(
                shape.fill(
                    on
                        ? blue.opacity(skin.opacity.o16)
                        : skin.color(.palette("foreground", hovering ? skin.opacity.o08 : skin.opacity.o05)))
            )
            .overlay(shape.strokeBorder(blue.opacity(skin.opacity.o50), lineWidth: 1).opacity(on ? 1 : 0))
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: hovering)
        .help(title)
    }
}
