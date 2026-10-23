import AinkradAppKit
import SwiftUI

/// The window after the first connect: sidebar and the selected screen. The shared states of mockup 11 live here —
/// offline with cached data (B), catching up after a reconnect (C), first load (D).
struct ShellView: View {
    @Bindable var store: CitadelStore
    @State private var screen: Screen = .home
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 0) {
            Sidebar(store: store, screen: $screen)
            VStack(alignment: .leading, spacing: 0) {
                if store.isShowingSettings {
                    PaneTitle(title: "Settings", crumb: nil)
                    SettingsView(store: store)
                } else {
                    PaneTitle(title: store.company?.name ?? CitadelApp.displayName, crumb: offlineCrumb)
                    if isOffline {
                        OfflineBar(store: store).transition(.move(edge: .top).combined(with: .opacity))
                    }
                    content
                        .opacity(isOffline ? skin.opacity.o45 : 1)
                        .saturation(isOffline ? skin.opacity.o60 : 1)
                        .allowsHitTesting(!isOffline)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: isOffline)
    }

    private var isOffline: Bool {
        if case .offline = store.phase { true } else { false }
    }

    /// "◌ offline · showing data from 3 min ago".
    private var offlineCrumb: Text? {
        guard isOffline else { return nil }
        let minutes = store.settings.document.lastSeen.map { Int(Date().timeIntervalSince($0) / 60) } ?? 0
        let age = minutes < 1 ? "just now" : "\(minutes) min ago"
        return Text("◌ offline · showing data from \(age)").foregroundStyle(status.warning)
    }

    @ViewBuilder
    private var content: some View {
        if case .catchingUp(let replayed) = store.streamStatus {
            CatchingUpView(replayed: replayed)
        } else if store.agentCount == nil, !isOffline {
            FirstLoadView()
        } else {
            AinkradEmptyState(
                icon: screen.icon, title: screen.title,
                message:
                    "This screen arrives in the next Citadel build. The connection, the company and its live events are ready."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}

/// The main pane's title row, with an optional crumb under it.
struct PaneTitle: View {
    let title: String
    let crumb: Text?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s2) {
            Text(title)
                .font(skin.font(AinkradFontToken(sizeKey: "t15", weight: "semibold"), typography: typo))
                .foregroundStyle(skin.color(skin.text.primary))
                .lineLimit(1)
            if let crumb {
                crumb.font(skin.font(AinkradFontToken(sizeKey: "t11"), typography: typo))
            }
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.top, skin.size.s14)
        .padding(.bottom, skin.size.s10)
    }
}
