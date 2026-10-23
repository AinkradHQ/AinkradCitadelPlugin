import AinkradAppKit
import SwiftUI

/// Screen 14 Project profile: the selected project's profile, repos and limits.
struct ProjectsView: View {
    let store: CitadelStore
    let model: CompanyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Projects", crumb: nil)
            Spacer(minLength: 0)
        }
    }
}
