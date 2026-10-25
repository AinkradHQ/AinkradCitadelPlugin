import Foundation
import Observation

/// Screens 03 Org and 04 Agent: what is open on them (the peek panel, a sheet, the agent drawer) and what they
/// loaded on top of the org chart. Kept on the company so a deep link, ⌘K or the sweep can stage any state.
@MainActor
@Observable
final class OrgPage {
    /// The sheets the org and agent screens open, one at a time.
    enum Sheet: Equatable {
        case pendingHires
        case structure(StructureTab)
        /// The five-step hire wizard: the team preselected from a cluster's Add, the step to open on.
        case hire(team: Int64?, step: Int)
        case team(Int64?)
        case department(Int64?)
        case role(String?)
        case editBudget(Int64)
        case changeModel(Int64)
        case appearance(Int64)
        case reassign(Int64)
        case terminate(Int64)
        case stopRun(Int64)
        case pause(Int64)
    }

    enum StructureTab: String, CaseIterable, Hashable {
        case departments = "Departments"
        case teams = "Teams"
        case roles = "Roles"
    }

    enum DrawerSection: String, CaseIterable, Hashable {
        case instructions = "Instructions"
        case skills = "Skills"
        case settings = "Settings"
    }

    /// Where a drawer opens: a section, and an anchor in it to scroll to (`budget`, `model`, `look`, `library`).
    struct Drawer: Equatable {
        var section: DrawerSection
        var anchor: String?
    }

    var filter: OrgFilter = .all
    /// The agent the peek panel shows.
    var picked: Int64?
    var sheet: Sheet?
    /// Read-only alias for switching over the open sheet.
    var openSheet: Sheet? { sheet }
    /// The sheet under a stacked one (Structure under its team / department / role form), shown again on close.
    var underSheet: Sheet?
    /// The last Structure tab shown (remembered, `APP.stTab`).
    var structureTab: StructureTab = .departments
    /// The chart's camera; kept while the screen is open, re-fit on resize until the person moves it.
    var camera = PanZoomCamera()
    var drawer: Drawer?
    /// The skill selected in the drawer's Skills section.
    var selectedSkill: String?

    /// Loaded for the wizard and the drawer: the pool's accounts (harness counts), runners (tag counts), the
    /// company's skills, each opened agent's resolved skills and fallback chain.
    var pool: [PoolAccount] = []
    var runners: [RunnerInfo] = []
    var skillLibrary: [SkillInfo] = []
    var agentSkills: [Int64: [SkillInfo]] = [:]
    var chains: [Int64: [FallbackEntry]] = [:]

    /// Opens `sheet` over the current one; `close()` returns to it.
    func stack(_ next: Sheet) {
        underSheet = sheet
        sheet = next
    }

    func close() {
        sheet = underSheet
        underSheet = nil
    }
}
