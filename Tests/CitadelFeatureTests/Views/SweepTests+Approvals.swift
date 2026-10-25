import Foundation

@testable import CitadelFeature

extension SweepTests {
    /// Screens 06 Approvals (each kind, answered, zero) and 08 Why stuck, on the prototype's data, at the prototype's
    /// window size, for side-by-side review with `/private/tmp/claude-501/parity02/*.png`.
    static func approvalsShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let size = CGSize(width: 1400, height: 900)
        var shots: [(String, CitadelStore, CGSize)] = []
        for (id, name) in [
            (Int64(21), "sprint"), (22, "merge"), (24, "budget"), (25, "hire"), (23, "permission"), (17, "answered"),
        ] {
            let store = stage(.approvals, nil, CompanyFixture.approvalsProto)
            store.selectedApproval = id
            shots.append(("p06-approvals-\(name)", store, size))
        }
        shots.append(
            (
                "p06-approvals-zero",
                stage(.approvals, nil) {
                    CompanyFixture.approvalsProto($0)
                    $0.approvals = []
                }, size
            ))
        shots.append(("p08-stuck", stage(.stuck, nil, CompanyFixture.stuckProto), size))
        shots.append(
            (
                "p08-stuck-slowing",
                stage(.stuck, nil) {
                    CompanyFixture.stuckProto($0)
                    $0.stuck.removeAll { !$0.isSlowing }
                }, size
            ))
        shots.append(("p08-stuck-zero", stage(.stuck, nil) { $0.stuck = [] }, size))
        return shots
    }
}
