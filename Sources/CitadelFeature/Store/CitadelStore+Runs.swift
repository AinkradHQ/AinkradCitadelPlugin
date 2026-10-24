import Foundation

/// The Runs screen: the company's newest runs, then run events keep them current (`reload(.run)`).
extension CitadelStore {
    func loadRunsPage() {
        guard let server, let model else { return }
        Task {
            // ponytail: one read per unknown issue; a batch issue read if the list grows past 100 runs.
            guard let runs = await server.companyRuns(company: model.companyID, limit: 100) else { return }
            model.companyRuns = runs
            for issue in Set(runs.compactMap(\.issueID)) where model.issues[issue] == nil {
                model.issues[issue] = await server.issue(issue)
            }
        }
    }
}
