import AinkradAppKit
import SwiftUI

/// The prototype's `.bar`: a 6 pt track with a cyan fill, amber from the warn line, red when `hard` and full.
struct MiniBar: View {
    let fraction: Double
    var warnAt = 0.8
    var height: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let h = height ?? skin.size.s6
        let tint =
            fraction >= 1
            ? skin.color(skin.palette.danger)
            : fraction >= warnAt ? skin.color(skin.palette.warning) : skin.color(skin.palette.accentSecondary)
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(skin.color(.palette("foreground", skin.opacity.o08)))
                Capsule().fill(tint).frame(width: geo.size.width * min(1, max(0, fraction)))
            }
        }
        .frame(height: h)
    }
}

/// Seven day bars `M T W T F S S` (peek panel `.op-week`, stage `.ak-wk`): a run is 6 pt, empty days a 3 pt stub.
struct WeekBars: View {
    let counts: [Int]
    var barWidth: CGFloat?
    var height: CGFloat?
    var unit: CGFloat?
    @State private var grown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let step = unit ?? skin.size.s6
        HStack(alignment: .bottom, spacing: barWidth == nil ? skin.size.s6 : skin.size.s3) {
            ForEach(Array(counts.enumerated()), id: \.offset) { index, count in
                VStack(spacing: skin.size.s4) {
                    Spacer(minLength: 0)
                    RoundedRectangle(cornerRadius: skin.size.s3)
                        .fill(
                            count > 0
                                ? skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o70)
                                : skin.color(.palette("foreground", skin.opacity.o10))
                        )
                        .frame(
                            maxWidth: barWidth ?? skin.size.s22,
                            minHeight: count > 0 ? step + CGFloat(min(count, 6)) * step : skin.size.s3,
                            maxHeight: count > 0 ? step + CGFloat(min(count, 6)) * step : skin.size.s3
                        )
                        .scaleEffect(y: grown || reduceMotion ? 1 : 0, anchor: .bottom)
                        .animation(
                            skin.animation(AinkradAnimationToken(curve: "spring", response: 0.6, damping: 0.8))
                                .delay(Double(index) * 0.06), value: grown)
                    Text(String("MTWTFSS".dropFirst(index).prefix(1))).citadelFont(
                        barWidth == nil ? "t9_5" : "t8_5", mono: true
                    )
                    .foregroundStyle(skin.color(skin.text.faint))
                }
                .frame(maxWidth: barWidth == nil ? .infinity : nil)
            }
        }
        .frame(height: height ?? skin.size.s56)
        .onAppear { grown = true }
    }
}

/// A small titled section of the peek panel (`.op-lbl`).
struct PeekLabel: View {
    let text: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(text).citadelFont("t10_5", weight: "semibold").foregroundStyle(skin.color(skin.text.faint))
    }
}

/// A run's end as the prototype's pill: succeeded ok, failed / runner lost / timed out err, cap hit warn.
struct RunStatePill: View {
    let run: RunInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View { StatePill(text: run.isLive ? "running" : run.endWord, tint: Self.tint(run, skin)) }

    static func tint(_ run: RunInfo, _ skin: AinkradSkin) -> Color {
        if run.isLive { return skin.color(skin.palette.accentSecondary) }
        switch run.endWord {
        case "succeeded": return skin.color(skin.palette.success)
        case "failed", "runner lost", "timed out": return skin.color(skin.palette.danger)
        case "cap hit": return skin.color(skin.palette.warning)
        default: return skin.color(skin.text.faint)
        }
    }
}

extension RunInfo {
    var duration: TimeInterval { (endedAt ?? Date()).timeIntervalSince(startedAt ?? queuedAt) }
}
