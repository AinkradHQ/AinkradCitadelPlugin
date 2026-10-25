import Foundation

@testable import CitadelFeature

extension SweepTests {
    /// The New company wizard, one shot per step: a named, filled-in draft over the prototype's pool and runners.
    static func newCompanyShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let size = CGSize(width: 1440, height: 900)
        let source = CompanyFixture.model()
        CompanyFixture.accountsParityPage(source)
        CompanyFixture.runnersPage(source)
        return (0..<NewCompanyDraft.steps.count).map { step in
            let store = stage(.home, nil) { _ in }
            var draft = NewCompanyDraft()
            draft.name = "Acme Robotics"
            draft.accounts = [1, 4]
            draft.step = step
            store.newCompany = NewCompanySession(
                draft: draft, pool: source.accountsPage.accounts, runners: source.runnersPage.runners)
            store.isCreatingCompany = true
            return ("12-newco-step\(step + 1)", store, size)
        }
    }
}
