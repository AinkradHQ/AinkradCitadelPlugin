import AinkradAppKit
import SwiftUI

/// The window's keyboard (prototype `ui.js`): ⌘1…⌘9 the sidebar rows, ⌘[ / ⌘] history, ⌘K search, ⌘N new
/// requirement, ⌘⇧O the company menu, ? the shortcuts sheet. Invisible buttons, so the keys work wherever focus
/// is in the pane.
struct ShellShortcuts: View {
    @Bindable var store: CitadelStore
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        ZStack {
            ForEach(Array(Screen.allCases.prefix(9).enumerated()), id: \.element) { index, screen in
                key(KeyEquivalent(Character("\(index + 1)"))) {
                    // The company menu's own ⌘1…⌘9 (its rows show the hint) win while it is open.
                    if store.isSwitchingCompany {
                        if store.companies.indices.contains(index) {
                            store.isSwitchingCompany = false
                            store.select(company: store.companies[index].id)
                        }
                    } else {
                        store.go(to: screen)
                    }
                }
            }
            key("[") { store.goBack() }
            key("]") { store.goForward() }
            key("k") { store.isSearching = true }
            key("n") { store.isComposingRequirement = true }
            key("o", modifiers: [.command, .shift]) { store.isSwitchingCompany = true }
            key("/", modifiers: [.shift]) { store.isShowingShortcuts = true }
        }
        .frame(width: 0, height: 0)
        .opacity(0)
        .accessibilityHidden(true)
        .ainkradPanelModal(isPresented: $store.isShowingShortcuts, contentWidth: skin.size.s420) { sheet }
    }

    private func key(
        _ key: KeyEquivalent, modifiers: EventModifiers = .command, action: @escaping () -> Void
    ) -> some View {
        AinkradTapArea(action: action) { Color.clear }.keyboardShortcut(key, modifiers: modifiers)
    }

    private static let rows: [(String, String)] = [
        ("⌘K", "Search everything"), ("⌘1 … ⌘9", "Go to a sidebar screen"), ("⌘[  ⌘]", "Back · forward"),
        ("⌘N", "New requirement"), ("⌘⇧O", "Switch company"), ("↑ ↓", "Move in a list"),
        ("⌘↵", "Approve / send"), ("⌘⌫", "Reject with a reason"), ("R", "Reply"), ("Esc", "Close the top layer"),
        ("?", "This sheet"),
    ]

    private var sheet: some View {
        VStack(alignment: .leading, spacing: skin.size.s14) {
            Text("Keyboard").citadelFont("t15", weight: "semibold")
            Grid(alignment: .leading, horizontalSpacing: skin.size.s14, verticalSpacing: skin.size.s10) {
                ForEach(Self.rows, id: \.0) { row in
                    GridRow {
                        Text(row.0).citadelFont("t12", weight: "semibold", mono: true)
                            .foregroundStyle(skin.color(skin.text.primary))
                            .padding(.horizontal, skin.size.s7)
                            .padding(.vertical, skin.size.s2)
                            .background(
                                skin.color(.palette("foreground", skin.opacity.o08)),
                                in: RoundedRectangle(cornerRadius: skin.size.s6))
                        Text(row.1).citadelFont("t12_5").foregroundStyle(skin.color(skin.text.muted))
                    }
                }
            }
            HStack {
                Spacer()
                AinkradButton(title: "Done", style: .primary) { store.isShowingShortcuts = false }.fixedSize()
            }
        }
    }
}
