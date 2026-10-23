import Foundation

@testable import CitadelFeature

extension SweepTests {
    /// Screens 12 Requirements and 13 Artifacts, at the mockups' window sizes (1280 × 1110, 1280 × 860).
    static func requirementsShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        [
            (
                "12-requirements", stage(.requirements, nil, CompanyFixture.requirementsPage),
                CGSize(width: 1280, height: 1110)
            ),
            (
                "12-requirement-cancel", stage(.requirements, nil, CompanyFixture.requirementsPage),
                CGSize(width: 1280, height: 900)
            ),
            ("13-artifacts", stage(.artifacts, nil, CompanyFixture.artifactsPage), CGSize(width: 1280, height: 860)),
        ]
    }
}
