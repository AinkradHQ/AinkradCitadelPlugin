import Foundation

@testable import CitadelFeature

extension SweepTests {
    /// Screen 07 Agent threads at the prototype's 1400 × 900 window: Quill asking you (MKT-8), Kestrel's thread
    /// (CIT-42, live run), Rook's lost run (CIT-49), and the Asks you tab.
    static func threadsShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let size = CGSize(width: 1400, height: 900)
        func threads(_ key: ThreadKey?, _ edit: @escaping (CompanyModel) -> Void = { _ in }) -> CitadelStore {
            let store = stage(.threads, nil) {
                CompanyFixture.threadsParity($0)
                edit($0)
            }
            store.selectedThread = key
            return store
        }
        return [
            ("07-threads", threads(ThreadKey(agentID: 15, issueID: 8)), size),
            ("07-threads-kestrel", threads(ThreadKey(agentID: 4, issueID: 42)), size),
            ("07-threads-rook-lost", threads(ThreadKey(agentID: 8, issueID: 49)), size),
            ("07-threads-asks-tab", threads(nil) { $0.threadsPage.filter = .asksYou }, size),
        ]
    }
}
