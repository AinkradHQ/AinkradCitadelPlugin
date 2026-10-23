import Foundation

@testable import CitadelFeature

extension SweepTests {
    /// Screens 14 Project profile and 16 Limits, at the mockups' window sizes.
    static func settingsShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let limits = stage(.home, nil, CompanyFixture.limitsPage)
        limits.isShowingSettings = true
        return [
            (
                "14-project-settings", stage(.projects, nil, CompanyFixture.projectsPage),
                CGSize(width: 1280, height: 1700)
            ),
            ("16-limits", limits, CGSize(width: 1280, height: 1290)),
        ]
    }
}
