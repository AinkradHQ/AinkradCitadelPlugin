import AinkradAppKit
import SwiftUI

/// Where the main pane is: a sidebar screen, the detail opened from it, or Settings.
struct Route: Hashable {
    var screen: Screen
    var detail: Detail?
    var settings: Bool
}

/// The prototype's router transitions: a detail pushes in from the right, history back slides from the left,
/// siblings fade up. The old pane always leaves first (110 ms) so two screens are never drawn on top of each other.
enum NavDirection {
    case push, back, fade

    @MainActor func transition(_ skin: AinkradSkin, reduceMotion: Bool) -> AnyTransition {
        guard !reduceMotion else { return .opacity }
        // The old pane leaves in 110 ms; the new one waits for it.
        let gap = 0.11
        let leave = skin.animation(AinkradAnimationToken(curve: "easeIn", duration: gap))
        func arrive(_ seconds: Double) -> Animation {
            skin.animation(AinkradAnimationToken(curve: "easeOut", duration: seconds)).delay(gap)
        }
        switch self {
        case .push:
            return .asymmetric(
                insertion: .offset(x: skin.size.s28).combined(with: .opacity).animation(arrive(0.3)),
                removal: .offset(x: -skin.size.s16).combined(with: .opacity).animation(leave))
        case .back:
            return .asymmetric(
                insertion: .offset(x: -skin.size.s28).combined(with: .opacity).animation(arrive(0.28)),
                removal: .offset(x: skin.size.s16).combined(with: .opacity).animation(leave))
        case .fade:
            return .asymmetric(
                insertion: .offset(y: skin.size.s8).combined(with: .opacity).animation(arrive(0.26)),
                removal: .offset(y: -skin.size.s4).combined(with: .opacity).animation(leave))
        }
    }
}

extension CitadelStore {
    var route: Route { Route(screen: screen, detail: detail, settings: isShowingSettings) }

    var canGoBack: Bool { historyIndex > 0 }
    var canGoForward: Bool { historyIndex < history.count - 1 }

    /// One history entry per settled route: a screen change and its detail reset land as one step.
    func recordRoute() {
        guard !isTravelling, !routePending else { return }
        routePending = true
        Task { @MainActor in
            routePending = false
            let now = route
            guard history.indices.contains(historyIndex) ? history[historyIndex] != now : true else { return }
            history = Array(history.prefix(historyIndex + 1)) + [now]
            historyIndex = history.count - 1
        }
    }

    func goBack() { travel(by: -1) }
    func goForward() { travel(by: 1) }

    private func travel(by step: Int) {
        let target = historyIndex + step
        guard history.indices.contains(target) else { return }
        isTravelling = true
        let destination = history[target]
        historyIndex = target
        screen = destination.screen
        detail = destination.detail
        isShowingSettings = destination.settings
        navDirection = step < 0 ? .back : .push
        isTravelling = false
    }

    /// ⌘1…⌘9: the sidebar rows in order.
    func go(to screen: Screen) {
        self.screen = screen
        detail = nil
        isShowingSettings = false
    }
}
