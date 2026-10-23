import AinkradAppKit
import SwiftUI

/// Screen 12 Requirements: the requirement list, the open thread with the CEO and its live plan.
struct RequirementsView: View {
    let store: CitadelStore
    let model: CompanyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Requirements", crumb: nil)
            Spacer(minLength: 0)
        }
    }
}
