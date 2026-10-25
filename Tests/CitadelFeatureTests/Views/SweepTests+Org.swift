import Foundation

@testable import CitadelFeature

extension SweepTests {
    /// Screens 03 Org and 04 Agent: the peek panel, every sheet, the hire wizard's steps, the agent drawer.
    static func orgShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let size = CGSize(width: 1400, height: 900)
        func org(_ name: String, _ apply: @escaping (OrgPage) -> Void) -> (String, CitadelStore, CGSize) {
            (
                name,
                stage(.org, nil) {
                    CompanyFixture.inboxPage($0)
                    CompanyFixture.orgPeekRuns($0)
                    apply($0.orgPage)
                }, size
            )
        }
        func agent(_ name: String, _ apply: @escaping (OrgPage) -> Void) -> (String, CitadelStore, CGSize) {
            (
                name,
                stage(.org, .agent(4)) {
                    CompanyFixture.agentPage($0)
                    apply($0.orgPage)
                }, size
            )
        }
        var shots = [
            org("03-org-peek") { $0.picked = 4 },
            org("03-org-hires") {
                $0.sheet = .pendingHires
            },
            org("03-org-structure-departments") { $0.sheet = .structure(.departments) },
            org("03-org-structure-teams") {
                $0.sheet = .structure(.teams)
                $0.structureTab = .teams
            },
            org("03-org-structure-roles") {
                $0.sheet = .structure(.roles)
                $0.structureTab = .roles
            },
            org("03-org-team-edit") { $0.sheet = .team(nil) },
            org("03-org-role-edit") { $0.sheet = .role(nil) },
            agent("04-agent-drawer-settings") { $0.drawer = .init(section: .settings, anchor: nil) },
            agent("04-agent-drawer-instructions") { $0.drawer = .init(section: .instructions, anchor: nil) },
            agent("04-agent-drawer-skills") { $0.drawer = .init(section: .skills, anchor: nil) },
            agent("04-agent-budget") { $0.sheet = .editBudget(4) },
            agent("04-agent-model") { $0.sheet = .changeModel(4) },
            agent("04-agent-terminate") { $0.sheet = .terminate(4) },
        ]
        for step in 0..<5 { shots.append(org("03-hire-step\(step + 1)") { $0.sheet = .hire(team: nil, step: step) }) }
        return shots
    }
}
