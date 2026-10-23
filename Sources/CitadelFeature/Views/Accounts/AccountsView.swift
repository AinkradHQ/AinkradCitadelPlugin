import AinkradAppKit
import SwiftUI

/// Screen 15 Accounts: the provider account pool, usage windows and fallback chains.
struct AccountsView: View {
    let store: CitadelStore
    let model: CompanyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Accounts", crumb: nil)
            Spacer(minLength: 0)
        }
    }
}
