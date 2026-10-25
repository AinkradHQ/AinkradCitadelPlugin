import AinkradAppKit
import SwiftUI

/// Screen 01: server URL + device key, and every connection state — connecting, connected, 401, offline. One
/// card; only its status block and buttons change between states.
struct ConnectView: View {
    @Bindable var store: CitadelStore
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    @State private var breathe = false

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        ZStack {
            // The breathing cyan glow behind the card.
            RadialGradient(
                colors: [skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o16), .clear], center: .center,
                startRadius: 0, endRadius: skin.size.s260
            )
            .frame(width: skin.size.s520, height: skin.size.s520)
            .scaleEffect(breathe ? 1.12 : 1)
            .allowsHitTesting(false)
            VStack(alignment: .leading, spacing: skin.size.s12) {
                HStack(spacing: skin.size.s14) {
                    mark
                    VStack(alignment: .leading, spacing: skin.size.s2) {
                        Text("Citadel").citadelFont("t10_5", weight: "semibold").foregroundStyle(
                            skin.color(skin.text.muted))
                        Text("Connect to your Citadel").citadelFont("t18", weight: "bold")
                            .foregroundStyle(skin.color(skin.text.primary))
                    }
                }
                Text(
                    "Citadel runs your agent company on a server. This Mac watches it, answers approvals and talks to agents."
                )
                .citadelFont("t13")
                .foregroundStyle(skin.color(skin.text.muted))
                .lineSpacing(skin.size.s3)
                .fixedSize(horizontal: false, vertical: true)
                form.padding(.top, skin.size.s4)
                ConnectStatusBlock(store: store)
                    .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: store.phase)
                actions.padding(.top, skin.size.s4)
            }
            .padding(.vertical, skin.size.s26)
            .padding(.horizontal, skin.size.s28)
            .frame(width: skin.size.s480 + skin.size.s20)
            .background(shape.fill(skin.color(.palette("surfaceElevated", skin.opacity.o60))))
            .background(.ultraThinMaterial, in: shape)
            .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o12)), lineWidth: 1))
        }
        .padding(skin.size.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 3)).repeatForever()) {
                breathe = true
            }
        }
    }

    /// The brand: an Orb whose mood follows the connection (idle, loading, success, confused on a 401, sleepy offline).
    private var mark: some View {
        AinkradAgentFigure(
            name: "Citadel", state: mood, palette: .neonTide, harness: nil, size: skin.size.s72, isActive: true,
            image: nil
        )
        .accessibilityHidden(true)
    }

    private var mood: AinkradFigureState {
        switch store.phase {
        case .setup: .idle
        case .connecting: .loading
        case .connected: .success
        case .rejected: .confused
        case .offline: .sleepy
        }
    }

    private var form: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            row("Server") {
                AinkradTextField(text: $store.serverDraft, placeholder: "https://citadel.example.com")
                    .monospaced()
                    .onReturn { _ in store.connect() }
            }
            row("Device key") { keyField }
            row(nil) {
                VStack(alignment: .leading, spacing: skin.size.s4) {
                    if let problem = store.formProblem {
                        Text(problem)
                            .font(skin.font(AinkradFontToken(sizeKey: "t11"), typography: typo))
                            .foregroundStyle(status.danger)
                    }
                    (Text("Create one on the server: ")
                        + Text(verbatim: "citadel-server device add <db> \"\(Self.macName)\"")
                        .font(skin.font(AinkradFontToken(sizeKey: "t11", mono: "family"), typography: typo)))
                        .font(skin.font(AinkradFontToken(sizeKey: "t11"), typography: typo))
                        .foregroundStyle(skin.color(skin.text.faint))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }

    /// One form row: the caps label in a 110 pt column, the control taking the rest.
    private func row<Control: View>(_ title: String?, @ViewBuilder control: () -> Control) -> some View {
        HStack(spacing: skin.size.s14) {
            label(title ?? "")
            control().frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    @ViewBuilder
    private var keyField: some View {
        if store.phase == .rejected {
            // The refused key, masked, in red: nothing about it was stored.
            AinkradTextField(text: .constant(DeviceKeyStore.masked(store.keyDraft)), placeholder: "")
                .monospaced()
                .disabled(true)
                .overlay(
                    fieldShape.stroke(status.danger.opacity(skin.opacity.o70), lineWidth: 1)
                        .allowsHitTesting(false)
                )
                .modifier(Shake(trigger: store.phase == .rejected && !reduceMotion))
        } else {
            AinkradSecureField(
                text: $store.keyDraft,
                placeholder: store.storedKey.map { DeviceKeyStore.masked($0, dots: 16) } ?? "ck_…")
        }
    }

    /// This Mac's name for the hint, read once (it can take a moment).
    private static let macName = Host.current().localizedName ?? "My Mac"

    private var fieldShape: AinkradSkinShape { AinkradSkinShape(token: skin.roles.field.shape) }

    private func label(_ text: String) -> some View {
        Text(skin.labelCased(text))
            .font(skin.font(AinkradFontToken(sizeKey: "t10", weight: "semibold"), typography: typo))
            .tracking(skin.usesNativeGlass ? 0 : skin.size.s1)
            .foregroundStyle(skin.color(skin.text.muted))
            .frame(width: skin.size.s110, alignment: .leading)
    }

    @ViewBuilder
    private var actions: some View {
        HStack(spacing: skin.size.s8) {
            switch store.phase {
            case .setup:
                Spacer(minLength: 0)
                if store.settings.document.hasConnected {
                    AinkradButton(title: "Cancel", style: .ghost) { store.resume() }.borderless().secondaryAccent()
                        .fixedSize()
                }
                AinkradDockButton("Connect ↵", tone: .primary) { store.connect() }
                    .keyboardShortcut(.return, modifiers: [])
            case .connecting:
                Spacer(minLength: 0)
                AinkradButton(title: "Cancel", style: .ghost) { store.cancel() }.borderless().secondaryAccent()
                    .keyboardShortcut(.cancelAction)
                    .fixedSize()
                AinkradDockButton("Connecting…", tone: .primary, isEnabled: false) {}
            case .connected:
                Spacer(minLength: 0)
                AinkradDockButton("Open Home", tone: .primary) { store.openHome() }
                    .keyboardShortcut(.return, modifiers: [])
            case .rejected:
                AinkradButton(title: "How keys work", style: .ghost) { store.showsKeyHelp.toggle() }
                    .borderless().secondaryAccent().fixedSize()
                Spacer(minLength: 0)
                AinkradDockButton("Paste new key", tone: .primary) {
                    store.keyDraft = ""
                    store.editConnection()
                }
            case .offline:
                AinkradButton(title: "Change server", style: .ghost) { store.editConnection() }
                    .borderless().secondaryAccent().fixedSize()
                Spacer(minLength: 0)
                AinkradDockButton("Retry now", tone: .primary) { store.retryNow() }
            }
        }
    }
}

/// A 401 shakes the key field once: 3 pt, two cycles (mockup 01 note 6); still under Reduce Motion.
private struct Shake: ViewModifier {
    let trigger: Bool
    @State private var progress: CGFloat = 0
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo

    func body(content: Content) -> some View {
        content
            .modifier(ShakeEffect(amount: skin.size.s3, animatableData: progress))
            .onAppear {
                guard trigger else { return }
                withAnimation(skin.animation(skin.motion.present)) { progress = 1 }
            }
    }
}

private struct ShakeEffect: GeometryEffect {
    var amount: CGFloat
    var animatableData: CGFloat

    func effectValue(size: CGSize) -> ProjectionTransform {
        ProjectionTransform(CGAffineTransform(translationX: amount * sin(animatableData * .pi * 4), y: 0))
    }
}
