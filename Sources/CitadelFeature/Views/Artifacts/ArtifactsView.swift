import AinkradAppKit
import SwiftUI

/// Screen 13 Artifacts: the company's published files and the open preview.
struct ArtifactsView: View {
    let store: CitadelStore
    let model: CompanyModel

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Artifacts", crumb: nil)
            Spacer(minLength: 0)
        }
    }
}
