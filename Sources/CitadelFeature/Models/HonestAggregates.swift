import Foundation

/// The client half of R17 (API minor 19): what the Requirements and Home aggregates may claim. On an older server
/// every function falls back to what the app showed before.
enum HonestAggregates {
    /// The scope per day, only when every burndown day carries one.
    static func scope(_ days: [Int?]) -> [Int]? {
        let values = days.compactMap { $0 }
        return !days.isEmpty && values.count == days.count ? values : nil
    }

    /// The scope line to draw: needs the server gate and one value per burndown day.
    static func scopeLine(_ plan: PlanTree, supported: Bool) -> [Int]? {
        guard supported, let scope = plan.scope, scope.count == plan.burndown.count, scope.count > 1 else { return nil }
        return scope
    }

    /// The ETA words: the server's day, else "n/a" (API 19+ and `showsMissing`), else nothing as before.
    static func eta(_ eta: String?, supported: Bool, showsMissing: Bool = true, now: Date = Date()) -> String? {
        if let eta { return Fmt.eta(eta, now: now) }
        return supported && showsMissing ? "n/a" : nil
    }
}
