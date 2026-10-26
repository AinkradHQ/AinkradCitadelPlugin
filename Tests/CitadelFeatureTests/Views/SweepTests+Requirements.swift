import Foundation

@testable import CitadelFeature

extension SweepTests {
    /// Screens 12 Requirements and 13 Artifacts. Requirements at the prototype's 1400 × 900 window: R-12 (open ask),
    /// R-11 (plan to approve + Ask for changes), R-9 (drafting), R-7 (done), the plan / artifacts / preview drawer and
    /// the New requirement sheet.
    static func requirementsShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let size = CGSize(width: 1400, height: 900)
        func requirements(_ edit: @escaping (RequirementsPage) -> Void) -> CitadelStore {
            stage(.requirements, nil) {
                CompanyFixture.requirementsPage($0)
                edit($0.requirementsPage)
            }
        }
        let sheet = requirements { _ in }
        sheet.isComposingRequirement = true
        return [
            ("12-requirements", requirements { _ in }, size),
            (
                "12-requirements-r11-changes",
                requirements {
                    $0.selectedID = 11
                    $0.askingChanges = true
                }, size
            ),
            ("12-requirements-r9-drafting", requirements { $0.selectedID = 9 }, size),
            (
                "12-requirements-r7-done",
                requirements {
                    $0.selectedID = 7
                    $0.filter = .done
                }, size
            ),
            ("12-requirements-plan-drawer", requirements { $0.drawer = [.plan] }, size),
            ("12-requirements-artifacts-drawer", requirements { $0.drawer = [.artifacts] }, size),
            ("12-requirements-artifact-preview", requirements { $0.drawer = [.artifacts, .artifact(102)] }, size),
            (
                "12-requirements-item-drawer",
                stage(.requirements, nil) {
                    CompanyFixture.requirementsPage($0)
                    CompanyFixture.projectWorkPage($0)
                    $0.requirementsPage.selectedID = 12
                    $0.requirementsPage.drawer = [.plan, .item(42)]
                }, size
            ),
            ("12-requirements-new-sheet", sheet, size),
            (
                "12-requirement-cancel", stage(.requirements, nil, CompanyFixture.requirementsPage),
                CGSize(width: 1280, height: 900)
            ),
            ("13-artifacts", stage(.artifacts, nil, CompanyFixture.artifactsPage), CGSize(width: 1280, height: 860)),
        ]
    }
}
