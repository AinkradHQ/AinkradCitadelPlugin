import AinkradAppKit
import SwiftUI

/// Screen 10 Runners: each runner's state, harnesses and disk.
struct RunnersView: View {
    let store: CitadelStore
    let model: CompanyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Runners", crumb: nil)
            Spacer(minLength: 0)
        }
    }
}
