// kit-candidate: AinkradSlider has no step snap on release, no server-default tick, no tint, no read-only variant and
// no live-value callback (spec 06 K17). The prototype's `.lm-t` gauge, shared by Settings › Limits and the New company
// wizard's budget.
import AinkradAppKit
import SwiftUI

/// A thin tinted track with a white knob: it follows the pointer 1:1 while dragged, settles onto `step` on release
/// with a spring, and ←/→ step it from the keyboard. `mark` draws a tick (the server default, a warn line). Read-only
/// (`isEnabled == false`) it draws at reduced opacity and takes no input. Never an invisible slider: the track is
/// painted from the pointer.
struct DragGauge: View {
    let value: Double
    let range: ClosedRange<Double>
    var step: Double = 1
    var mark: Double?
    let tint: Color
    var isEnabled = true
    var label: String
    var valueText: (Double) -> String = { $0.formatted() }
    /// The snapped value while dragging (live labels).
    var onChange: ((Double) -> Void)?
    /// The snapped value on release or a key step, when it differs from `value`.
    var onCommit: (Double) -> Void = { _ in }

    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var dragged: Double?
    @State private var pending: Double?
    @State private var lastSnap: Double?
    @State private var hovering = false
    @FocusState private var focused: Bool

    private var shown: Double { dragged ?? pending ?? value }

    var body: some View {
        GeometryReader { geo in
            let width = geo.size.width
            let x = fraction(shown) * width
            let knob = skin.size.s12
            ZStack(alignment: .leading) {
                Capsule().fill(skin.color(.palette("foreground", skin.opacity.o07)))
                Capsule()
                    .fill(
                        LinearGradient(
                            colors: [tint.opacity(skin.opacity.o40), tint], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: max(0, x))
                if let mark {
                    Rectangle().fill(skin.color(.palette("foreground", skin.opacity.o45)))
                        .frame(width: skin.size.s2, height: skin.size.s6 + skin.size.s8)
                        .offset(x: fraction(mark) * width - skin.size.s1)
                }
                Circle().fill(skin.color(.palette("foreground", 1)))
                    .frame(width: knob, height: knob)
                    // The 3 pt ring sits outside the white dot (`box-shadow: 0 0 0 3px`).
                    .background(
                        Circle().fill(isEnabled ? tint : skin.color(.palette("foreground", skin.opacity.o25)))
                            .padding(-skin.size.s3)
                    )
                    .shadow(color: isEnabled ? tint : .clear, radius: dragged == nil ? skin.size.s5 : skin.size.s8)
                    .scaleEffect(dragged != nil ? 1.35 : (hovering || focused) && isEnabled ? 1.25 : 1)
                    .offset(x: x - knob / 2)
            }
            .frame(height: skin.size.s6)
            .frame(maxHeight: .infinity)
            .contentShape(Rectangle())
            .gesture(drag(width: width), including: isEnabled ? .all : .none)
        }
        // The hit area reaches past the 6 pt track (`inset: -12px -6px`).
        .frame(height: skin.size.s6 + skin.size.s24)
        .opacity(isEnabled ? 1 : skin.opacity.o45)
        .onHover { hovering = $0 }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: hovering)
        .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: focused)
        .focusable(isEnabled)
        .focused($focused)
        .focusEffectDisabled()
        .onKeyPress(.leftArrow) { key(-1) }
        .onKeyPress(.rightArrow) { key(1) }
        .onChange(of: value) { _, _ in pending = nil }
        .accessibilityElement()
        .accessibilityLabel(label)
        .accessibilityValue(valueText(shown))
        .accessibilityAdjustableAction { direction in
            _ = key(direction == .increment ? 1 : direction == .decrement ? -1 : 0)
        }
    }

    private func fraction(_ v: Double) -> Double {
        let span = range.upperBound - range.lowerBound
        return span > 0 ? min(1, max(0, (v - range.lowerBound) / span)) : 0
    }

    private func snap(_ v: Double) -> Double {
        let low = range.lowerBound
        let stepped = low + ((v - low) / max(step, .leastNonzeroMagnitude)).rounded() * step
        return min(range.upperBound, max(low, stepped))
    }

    private func drag(width: CGFloat) -> some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { gesture in
                let raw =
                    range.lowerBound + (range.upperBound - range.lowerBound)
                    * min(1, max(0, gesture.location.x / max(width, 1)))
                var quiet = Transaction()
                quiet.disablesAnimations = true
                withTransaction(quiet) { dragged = raw }
                let snapped = snap(raw)
                if snapped != lastSnap {
                    lastSnap = snapped
                    onChange?(snapped)
                }
            }
            .onEnded { _ in
                let snapped = snap(dragged ?? value)
                // Settles onto the step (the prototype's `.3s cubic-bezier(.2,.9,.3,1.2)`).
                let settle = AinkradAnimationToken(curve: "spring", response: 0.3, damping: 0.7)
                withAnimation(reduceMotion ? nil : skin.animation(settle)) {
                    dragged = nil
                    pending = snapped
                }
                lastSnap = nil
                commit(snapped)
            }
    }

    private func key(_ direction: Double) -> KeyPress.Result {
        guard isEnabled, direction != 0 else { return .ignored }
        let next = snap(shown + direction * step)
        withAnimation(reduceMotion ? nil : skin.animation(skin.motion.hover)) { pending = next }
        onChange?(next)
        commit(next)
        return .handled
    }

    private func commit(_ v: Double) {
        guard v != value else {
            pending = nil
            return
        }
        onCommit(v)
        // A refused value never arrives as the new `value`: fall back to it.
        Task {
            try? await Task.sleep(for: .seconds(4))
            if pending == v { pending = nil }
        }
    }
}

/// `min · server X · max` under a gauge (10 pt mono, faint).
struct GaugeLegend: View {
    let low: String
    let middle: String
    let high: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack {
            Text(low)
            Spacer(minLength: skin.size.s4)
            Text(middle)
            Spacer(minLength: skin.size.s4)
            Text(high)
        }
        .citadelFont("t9_5", mono: true).foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
    }
}
