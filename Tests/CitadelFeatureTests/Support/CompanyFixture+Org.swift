import Foundation

@testable import CitadelFeature

extension CompanyFixture {
    /// The org peek's week for Kestrel (`03-org-peek`): 15 finished runs this week, 9 succeeded (60%), each $1.28.
    /// Days are spread from Monday to today, so the week bars fill in on whatever day the sweep runs.
    static func orgPeekRuns(_ model: CompanyModel) {
        var calendar = Calendar.current
        calendar.firstWeekday = 2
        let weekday = calendar.component(.weekday, from: now)  // Sunday = 1
        let daysIntoWeek = (weekday + 5) % 7  // Monday = 0 … Sunday = 6
        model.agentRuns[4] = (0..<15).map { index in
            ended(
                500 + Int64(index), issue: 38, state: index < 9 ? "succeeded" : "failed",
                daysAgo: Double(index % (daysIntoWeek + 1)), minutes: Double(6 + index % 9), cost: 1_280_000)
        }
    }
}
