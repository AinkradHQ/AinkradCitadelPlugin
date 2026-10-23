import AinkradAppKit
import SwiftUI

/// Company settings (⚙ next to the switcher): its sections, Limits (screen 16) among them.
struct CompanySettingsView: View {
    let store: CitadelStore

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Settings", crumb: nil)
            SettingsView(store: store)
        }
    }
}
