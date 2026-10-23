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

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: 0) {
                mark
                Text("Connect to your Citadel")
                    .font(skin.font(AinkradFontToken(sizeKey: "t18", weight: "bold"), typography: typo))
                    .foregroundStyle(skin.color(skin.text.primary))
                    .padding(.top, skin.size.s10)
                    .padding(.bottom, skin.size.s4)
                Text(
                    "Citadel runs your agent company on a server. This Mac watches it, answers approvals and talks to agents."
                )
                .font(skin.font(AinkradFontToken(sizeKey: "t13"), typography: typo))
                .foregroundStyle(skin.color(skin.text.muted))
                .lineSpacing(skin.size.s3)
                .fixedSize(horizontal: false, vertical: true)
                form.padding(.top, skin.size.s16)
                ConnectStatusBlock(store: store)
                    .padding(.top, skin.size.s16)
                    .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: store.phase)
                actions.padding(.top, skin.size.s12)
            }
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s10)
        }
        .frame(width: skin.size.s460)
        .padding(skin.size.s20)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }

    private var mark: some View {
        let shape =
            skin.usesNativeGlass
            ? AnyShape(RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous))
            : AnyShape(skin.shape(cut: skin.size.s10))
        return Text("⛫")
            .font(skin.font(AinkradFontToken(sizeKey: "t20"), typography: typo))
            .foregroundStyle(theme.accentSecondary)
            .frame(width: skin.size.s44, height: skin.size.s44)
            .background(shape.fill(theme.surface.opacity(skin.opacity.o90)))
            .overlay(shape.stroke(theme.accentSecondary.opacity(skin.opacity.o35), lineWidth: 1))
            .accessibilityHidden(true)
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
                AinkradButton(title: "Connect ↵", style: .primary) { store.connect() }
                    .keyboardShortcut(.return, modifiers: [])
                    .fixedSize()
            case .connecting:
                Spacer(minLength: 0)
                AinkradButton(title: "Cancel", style: .ghost) { store.cancel() }.borderless().secondaryAccent()
                    .keyboardShortcut(.cancelAction)
                    .fixedSize()
                // Stays lit while connecting (mockup 01); the status block carries the progress.
                AinkradButton(title: "Connect ↵", style: .primary) {}.fixedSize()
            case .connected:
                AinkradButton(title: "Open Home", style: .primary) { store.openHome() }
                    .keyboardShortcut(.return, modifiers: [])
                    .fixedSize()
                Spacer(minLength: 0)
            case .rejected:
                AinkradButton(title: "Paste new key", style: .secondary) {
                    store.keyDraft = ""
                    store.editConnection()
                }
                .fixedSize()
                AinkradButton(title: "How keys work", style: .ghost) { store.showsKeyHelp.toggle() }
                    .borderless().secondaryAccent().fixedSize()
                Spacer(minLength: 0)
            case .offline:
                AinkradButton(title: "Retry now", style: .secondary) { store.retryNow() }.fixedSize()
                AinkradButton(title: "Change server", style: .ghost) { store.editConnection() }
                    .borderless().secondaryAccent().fixedSize()
                Spacer(minLength: 0)
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
