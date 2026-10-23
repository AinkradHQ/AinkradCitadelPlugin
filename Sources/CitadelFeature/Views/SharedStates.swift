import AinkradAppKit
import SwiftUI

/// Mockup 11 B: the slim amber bar over the current screen while the server is unreachable after a first connect.
/// Cached data stays below it, dimmed.
struct OfflineBar: View {
    let store: CitadelStore
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let shape =
            skin.usesNativeGlass
            ? AnyShape(Capsule())
            : AnyShape(RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous))
        HStack(spacing: skin.size.s10) {
            Image(systemName: "circle.dotted").foregroundStyle(status.warning)
            TimelineView(.periodic(from: .now, by: 1)) { context in
                message(now: context.date)
                    .lineLimit(2)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: skin.size.s6)
            AinkradButton(title: "Retry now", style: .secondary) { store.retryNow() }
                .secondaryAccent().compact().fixedSize()
        }
        .font(skin.font(AinkradFontToken(sizeKey: "t12"), typography: typo))
        .foregroundStyle(skin.color(skin.text.muted))
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s7)
        .background(shape.fill(status.warning.opacity(skin.opacity.o10)))
        .padding(.horizontal, skin.size.s20)
        .padding(.bottom, skin.size.s8)
    }

    private func message(now: Date) -> Text {
        guard case .offline(let attempt, let retryAt, _) = store.phase else { return Text("") }
        let seconds = ConnectStatusBlock.seconds(until: retryAt, from: now)
        return Text("Can't reach \(store.host) — retrying in ")
            + Text(verbatim: "\(seconds)s").font(
                skin.font(AinkradFontToken(sizeKey: "t12", mono: "family"), typography: typo))
            + Text(verbatim: " (attempt \(attempt)). ")
            + Text("Approvals and chat are paused until it's back.")
    }
}

/// Mockup 11 C: real replay progress after a reconnect — never an endless spinner.
struct CatchingUpView: View {
    let replayed: Int
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        VStack(spacing: skin.size.s8) {
            AinkradSpinner(size: skin.size.s18)
            Text("Catching up")
                .font(skin.font(AinkradFontToken(sizeKey: "t14", weight: "bold"), typography: typo))
                .foregroundStyle(skin.color(skin.text.primary))
            Text(verbatim: "Replayed \(replayed.formatted()) events since you were last here")
                .font(skin.font(AinkradFontToken(sizeKey: "t12_5"), typography: typo))
                .foregroundStyle(skin.color(skin.text.muted))
        }
        .multilineTextAlignment(.center)
        .padding(.horizontal, skin.size.s30)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .accessibilityElement(children: .combine)
    }
}

/// Mockup 11 D: shimmer rows shaped like the real rows, so nothing jumps when the list arrives.
struct FirstLoadView: View {
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        VStack(spacing: skin.size.s14) {
            AinkradSkeletonRow()
            AinkradSkeletonRow(widthFraction: 0.7)
            AinkradSkeletonRow(widthFraction: 0.85)
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.vertical, skin.size.s16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
    }
}
