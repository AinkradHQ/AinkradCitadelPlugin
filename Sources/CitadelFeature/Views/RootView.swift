import AinkradAppKit
import SwiftUI

/// The window: the connect card on first run (or when the key stops working), the shell otherwise.
struct RootView: View {
    let store: CitadelStore
    let theme: HostTheme
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            if store.showsConnectCard {
                ConnectView(store: store)
                    .transition(.asymmetric(insertion: .opacity, removal: .opacity.combined(with: .scale(scale: 0.98))))
            } else {
                ShellView(store: store).transition(.opacity)
            }
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: store.showsConnectCard)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(theme.tokens.background)
        .foregroundStyle(theme.tokens.foreground)
        .ainkradHostTheme(theme)
        .task { store.start() }
    }
}
