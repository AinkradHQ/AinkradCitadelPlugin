import AinkradAppKit
import SwiftUI

/// 11 B (prototype `offline-bar`): the amber bar at the top of the pane while the server is unreachable after a
/// first connect — how old the data is, the attempt and the countdown, and Retry now (always live).
struct OfflineBar: View {
    let store: CitadelStore
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        HStack(spacing: skin.size.s10) {
            TimelineView(.periodic(from: .now, by: 1)) { context in
                message(now: context.date).lineLimit(2).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: skin.size.s6)
            AinkradDockButton("Retry now", height: skin.size.s26) { store.retryNow() }
        }
        .citadelFont("t12")
        .foregroundStyle(skin.color(skin.text.muted))
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s8)
        .background(status.warning.opacity(skin.opacity.o12), in: RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous))
        .padding(.horizontal, skin.size.s14)
        .padding(.bottom, skin.size.s6)
    }

    /// "⚠ **Can't reach host** · showing what was last synced 2m ago · attempt 4, next in **8s**".
    private func message(now: Date) -> Text {
        guard case .offline(let attempt, let retryAt, _) = store.phase else { return Text("") }
        let seconds = ConnectStatusBlock.seconds(until: retryAt, from: now)
        let minutes = store.settings.document.lastSeen.map { Int(now.timeIntervalSince($0) / 60) } ?? 0
        let age = minutes < 1 ? "just now" : "\(minutes)m ago"
        return Text("⚠ ").foregroundStyle(status.warning)
            + Text("Can't reach \(store.host)").bold().foregroundStyle(skin.color(skin.text.primary))
            + Text(" · showing what was last synced \(age) · attempt \(attempt), next in ")
            + Text(verbatim: "\(seconds)s").bold().foregroundStyle(skin.color(skin.text.primary))
    }
}

/// Mockup 11 C: real replay progress after a reconnect — never an endless spinner.
struct CatchingUpView: View {
    let replayed: Int
    /// How many there are to replay, when the server said (`GET /me`).
    var total: Int?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        VStack(spacing: skin.size.s8) {
            AinkradSpinner(size: skin.size.s18)
            Text("Catching up")
                .font(skin.font(AinkradFontToken(sizeKey: "t14", weight: "bold"), typography: typo))
                .foregroundStyle(skin.color(skin.text.primary))
            Text(verbatim: progressLine)
                .font(skin.font(AinkradFontToken(sizeKey: "t12_5"), typography: typo))
                .foregroundStyle(skin.color(skin.text.muted))
            if let total, total > 0 {
                AinkradBudgetBar(
                    label: "Catching up", value: Double(min(replayed, total)), limit: Double(total),
                    warnFraction: nil, showsHardLimit: false, tone: .progress(Double(replayed), of: Double(total))
                )
                .frame(width: skin.size.s240)
            }
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, skin.size.s30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }

    private var progressLine: String {
        guard let total, total > 0 else { return "Replayed \(replayed.formatted()) events since you were last here" }
        return "Replayed \(min(replayed, total).formatted()) of \(total.formatted()) events since you were last here"
    }
}

/// 11 D (prototype `_skeleton`): the shape of Home while the company loads — header bars, four tiles, six avatar
/// rows — shimmering, so nothing jumps when the data arrives.
struct FirstLoadView: View {
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s14) {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                bar(width: skin.size.s180, height: skin.size.s16)
                bar(width: skin.size.s300, height: skin.size.s10)
            }
            HStack(spacing: skin.size.s14) {
                ForEach(0..<4, id: \.self) { _ in
                    BentoTile {
                        VStack(alignment: .leading, spacing: skin.size.s10) {
                            GeometryReader { geo in bar(width: geo.size.width * 0.5, height: skin.size.s12) }
                                .frame(height: skin.size.s12)
                            GeometryReader { geo in bar(width: geo.size.width * 0.4, height: skin.size.s26) }
                                .frame(height: skin.size.s26)
                        }
                    }
                }
            }
            BentoTile {
                VStack(alignment: .leading, spacing: skin.size.s14) {
                    ForEach(0..<6, id: \.self) { index in
                        HStack(spacing: skin.size.s10) {
                            Circle().fill(fill).frame(width: skin.size.s24, height: skin.size.s24)
                            VStack(alignment: .leading, spacing: skin.size.s6) {
                                bar(width: skin.size.s220, height: skin.size.s10)
                                bar(width: skin.size.s140, height: skin.size.s8)
                            }
                        }
                        .opacity(1 - Double(index) * 0.12)
                    }
                }
            }
        }
        .ainkradShimmer()
        .padding(.horizontal, skin.size.s20)
        .padding(.vertical, skin.size.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }

    private var fill: Color { skin.color(.palette("foreground", skin.opacity.o07)) }

    private func bar(width: CGFloat, height: CGFloat) -> some View {
        RoundedRectangle(cornerRadius: skin.size.s4, style: .continuous).fill(fill).frame(width: width, height: height)
    }
}
