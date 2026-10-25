import Foundation

@testable import CitadelFeature

extension SweepTests {
    /// Lane 4: Runs (stage, peeks, the project picker), Run (live #418 waiting, ended #422), Artifacts (grid, list,
    /// peek, Quick Look), at the prototype's 1440 × 900 window less its frame.
    static func runsShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let size = CGSize(width: 1400, height: 900)
        let runs: (CompanyModel) -> Void = CompanyFixture.runsParity
        let waiting: (CompanyModel) -> Void = {
            CompanyFixture.runsParity($0)
            $0.approvals.append(
                ApprovalInfo(
                    id: 9, kind: "permission_escalation", agentID: 4, issueID: 42, requestedBy: 4, expiresAt: nil,
                    fields: [
                        "run": "418", "request": "r7", "tool": "Bash",
                        "input.command": "cargo add tokio-tungstenite@0.26 --features rustls",
                    ]))
        }
        let artifacts: (CompanyModel) -> Void = CompanyFixture.artifactsParity
        return [
            ("l4-01-runs", stage(.runs, nil, runs), size),
            (
                "l4-02-runs-peek-422",
                stage(.runs, nil) {
                    runs($0)
                    $0.runsPage.peekID = 422
                }, size
            ),
            (
                "l4-03-runs-peek-418",
                stage(.runs, nil) {
                    runs($0)
                    $0.transcripts[418] = CompanyFixture.peek418Transcript()
                    $0.runsPage.peekID = 418
                }, size
            ),
            (
                "l4-04-runs-project-picker",
                stage(.runs, nil) {
                    runs($0)
                    $0.runsPage.openPicker = "project"
                }, size
            ),
            ("l4-05-run-418-live", stage(.runs, .run(418), runs), size),
            ("l4-06-run-422-ended", stage(.runs, .run(422), runs), size),
            ("l4-07-artifacts-grid", stage(.artifacts, nil, artifacts), size),
            (
                "l4-08-artifacts-list",
                stage(.artifacts, nil) {
                    artifacts($0)
                    $0.artifactsPage.isGrid = false
                }, size
            ),
            (
                "l4-09-artifacts-peek",
                stage(.artifacts, nil) {
                    artifacts($0)
                    $0.artifactsPage.selectedID = 101
                }, size
            ),
            (
                "l4-10-artifacts-quicklook",
                stage(.artifacts, nil) {
                    artifacts($0)
                    $0.artifactsPage.selectedID = 101
                    $0.artifactsPage.quickLookID = 101
                }, size
            ),
        ]
    }
}
