import AinkradAppKit
import SwiftUI

/// Settings › Members & devices › Pair a device (`addDevice`): the six-character code as tiles that pop in, a ring
/// counting down its five minutes, a radar while it waits for the device, and the device itself once it appears in
/// the key list. The list is read again while it waits.
struct PairDeviceDrawer: View {
    let store: CitadelStore
    let model: CompanyModel
    let close: @MainActor @Sendable () -> Void
    @Environment(\.ainkradSkin) private var skin

    private var page: LimitsPage { model.limitsPage }
    private static let lifetime: TimeInterval = 300

    var body: some View {
        let violet = skin.color(skin.palette.accentViolet)
        let session = page.pairing
        AinkradDrawerPanel(
            style: .form, onClose: close,
            header: { AinkradDrawerCrumb(["Settings", "Pair a device"], monospaced: true) }
        ) {
            AinkradDrawerHero(
                tint: violet, title: "Pair a device",
                subtitle: "On the new device open Citadel → Connect → Pair with code"
            ) {
                Image(systemName: "person.2").citadelFont("t20").foregroundStyle(violet)
                    .frame(width: skin.size.s52, height: skin.size.s52)
                    .background(
                        violet.opacity(skin.opacity.o18),
                        in: RoundedRectangle(cornerRadius: skin.size.s15, style: .continuous))
            } trailing: {
                EmptyView()
            }
            if let paired = session?.paired {
                paidBody(paired)
            } else if let code = session?.code {
                waiting(code)
            } else {
                ProgressView().frame(maxWidth: .infinity).padding(.vertical, skin.size.s30)
            }
        } footer: {
            Spacer()
            if session?.paired == nil {
                AinkradDockButton("Cancel", action: close)
            } else {
                AinkradDockButton("Done", tone: .primary, action: close)
            }
        }
        .task(id: session?.code?.code) {
            // The new device shows up in the key list (its `device.paired` event also asks for it).
            while !Task.isCancelled, page.pairing?.paired == nil, page.pairing?.code != nil {
                try? await Task.sleep(for: .seconds(2))
                store.loadDevices()
            }
        }
    }

    private func waiting(_ code: PairingCode) -> some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let left = max(0, code.expiresAt.timeIntervalSince(context.date))
            VStack(spacing: skin.size.s18) {
                AinkradDrawerSection(title: "Pairing code") {
                    HStack(spacing: skin.size.s6) {
                        ForEach(Array(code.tiles.enumerated()), id: \.offset) { index, tile in
                            PairCodeTile(character: tile, index: index, expired: left == 0)
                        }
                    }
                    .frame(maxWidth: .infinity)
                    HStack(spacing: skin.size.s12) {
                        AinkradRingGauge(
                            value: left / Self.lifetime, tint: skin.color(skin.palette.accentViolet),
                            diameter: skin.size.s56, lineWidth: skin.size.s5
                        ) {
                            Text(String(format: "%d:%02d", Int(left) / 60, Int(left) % 60))
                                .citadelFont("t12", weight: "semibold", mono: true)
                        }
                        Text(left == 0 ? "expired · ask for a new code" : "one use · expires when the ring empties")
                            .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                        Spacer(minLength: 0)
                        if left == 0 {
                            AinkradDockButton("New code", systemImage: "arrow.clockwise") { store.startPairing() }
                        }
                    }
                }
                if left > 0 {
                    RadarWait(
                        title: "Waiting for the device…", hint: "This updates by itself when it pairs.",
                        symbol: "iphone")
                }
                CommandStrip(command: "citadel key create --device \"iPad Pro\"")
            }
        }
    }

    private func paidBody(_ device: DeviceInfo) -> some View {
        let green = skin.color(skin.palette.success)
        return VStack(spacing: skin.size.s8) {
            Text("✓").citadelFont("t24", weight: "bold").foregroundStyle(green)
                .frame(width: skin.size.s56, height: skin.size.s56)
                .background(green.opacity(skin.opacity.o16), in: Circle())
            Text("\(device.name) paired").citadelFont("t15", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.primary))
            Text("push via the device's own key").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, skin.size.s30)
    }
}

/// One character of the code (`.sx-pair span`): it pops in a beat after the one before it; the dash is lighter.
private struct PairCodeTile: View {
    let character: String
    let index: Int
    let expired: Bool
    @State private var shown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let dash = character == "-"
        let violet = skin.color(skin.palette.accentViolet)
        Text(character).citadelFont("t24", weight: "bold", mono: true)
            .foregroundStyle(dash ? skin.color(skin.text.faint) : skin.color(skin.text.primary))
            .frame(width: dash ? skin.size.s16 : skin.size.s44, height: skin.size.s54)
            .background(
                dash ? .clear : violet.opacity(expired ? skin.opacity.o07 : skin.opacity.o16),
                in: RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
            )
            .opacity(expired && !dash ? skin.opacity.o50 : 1)
            .scaleEffect(shown || reduceMotion ? 1 : 0.6)
            .opacity(shown || reduceMotion ? 1 : 0)
            .onAppear {
                withAnimation(
                    skin.animation(AinkradAnimationToken(curve: "spring", response: 0.4, damping: 0.7))
                        .delay(Double(index) * 0.06)
                ) { shown = true }
            }
    }
}
