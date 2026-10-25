// kit-candidate: AinkradStepTrail (spec 02 K9) — the prototype's evidence trail (`.sk-trail`): step chips with an
// ok / warn / bad dot joined by short links a highlight flows along. Generic: plain strings and states.
import AinkradAppKit
import SwiftUI

struct TrailStep: Equatable {
    enum State { case ok, warn, bad }
    var label: String
    var state: State = .ok
    /// A mono detail after the label (`runner_lost`, `since 01:40`).
    var detail: String?
}

struct StepTrail: View {
    let steps: [TrailStep]
    /// Steps rise in one after another, after this delay.
    var delay: Double = 0
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradFlowLayout(spacing: 0, lineSpacing: skin.size.s6) {
            ForEach(Array(steps.enumerated()), id: \.offset) { index, step in
                HStack(spacing: 0) {
                    if index > 0 { TrailLink() }
                    chip(step).riseIn(delay: delay + Double(index) * 0.09)
                }
            }
        }
    }

    private func chip(_ step: TrailStep) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous)
        let (fg, dot, rim, fill): (Color, Color, Color, Color) =
            switch step.state {
            case .ok:
                (
                    skin.color(skin.text.muted), skin.color(skin.palette.success),
                    skin.color(.palette("foreground", skin.opacity.o07)),
                    skin.color(.palette("foreground", skin.opacity.o05))
                )
            case .warn:
                (
                    skin.color(skin.palette.warning), skin.color(skin.palette.warning),
                    skin.color(skin.palette.warning).opacity(skin.opacity.o30),
                    skin.color(.palette("foreground", skin.opacity.o05))
                )
            case .bad:
                (
                    skin.color(skin.palette.danger), skin.color(skin.palette.danger),
                    skin.color(skin.palette.danger).opacity(skin.opacity.o35),
                    skin.color(skin.palette.danger).opacity(skin.opacity.o08)
                )
            }
        return HStack(spacing: skin.size.s6) {
            Circle().fill(dot).frame(width: skin.size.s7, height: skin.size.s7)
                .shadow(color: step.state == .bad ? dot : .clear, radius: skin.size.s4)
            Text(step.label).citadelFont("t11")
            if let detail = step.detail {
                Text(detail).citadelFont("t10_5", mono: true).opacity(skin.opacity.o80)
            }
        }
        .foregroundStyle(fg)
        .padding(.horizontal, skin.size.s10)
        .frame(height: skin.size.s28)
        .background(fill, in: shape)
        .overlay(shape.strokeBorder(rim, lineWidth: 1))
    }
}

/// The 22×2 link between two steps, a highlight flowing along it (`skFlow 1.8s`).
private struct TrailLink: View {
    @State private var phase: CGFloat = 0
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let width = skin.size.s22
        LinearGradient(
            colors: [
                skin.color(.palette("foreground", skin.opacity.o08)),
                skin.color(.palette("foreground", skin.opacity.o22)),
            ], startPoint: .leading, endPoint: .trailing
        )
        .frame(width: width, height: skin.size.s2)
        .overlay(alignment: .leading) {
            if !reduceMotion {
                Rectangle().fill(skin.color(.palette("foreground", skin.opacity.o60)))
                    .frame(width: skin.size.s8)
                    .offset(x: -skin.size.s8 + phase * (width + skin.size.s8))
            }
        }
        .clipped()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                skin.animation(AinkradAnimationToken(curve: "linear", duration: 1.8)).repeatForever(autoreverses: false)
            ) { phase = 1 }
        }
    }
}
