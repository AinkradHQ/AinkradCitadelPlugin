import Foundation

/// The server's API minor gates what the app may write: an older Citadel answers 404 on a newer endpoint, so its
/// controls stay off with an honest line instead of failing on click.
extension CitadelStore {
    /// The API minor that added agent edits, wake/terminate, org structure writes, company look and account delete.
    static let structureMinor = 17
    /// The API minor of the second tranche: issue edits, epics, project profile and runtime, CFD, repo probe,
    /// requirement pause/done, stuck trails (B1) and dollar budgets, chain presets, roles, agent stats,
    /// notifications, device pairing (B2).
    static let trancheBMinor = 18
    /// The API minor that added `BurndownDay.scope` (R17): the burndown can draw the plan's scope, and a missing ETA
    /// is "n/a" instead of a gap.
    static let honestAggregatesMinor = 19
    var honestAggregates: Bool { serverSupports(minor: Self.honestAggregatesMinor) }

    /// Whether the connected server speaks API minor `minor` or newer (false until `/me` has answered).
    func serverSupports(minor: Int) -> Bool { (apiMinor ?? 0) >= minor }

    /// Help text for a control the server cannot back yet.
    static let needsServerUpdate = "Needs a Citadel server update (API 17)"
    static let needsServerUpdate18 = "Needs a Citadel server update (API 18)"

    /// The control's help: the line for an old server, else `ready`.
    func help(minor: Int = CitadelStore.structureMinor, ready: String = "") -> String {
        serverSupports(minor: minor) ? ready : "Needs a Citadel server update (API \(minor))"
    }
}
