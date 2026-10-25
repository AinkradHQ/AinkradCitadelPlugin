import Foundation

@testable import CitadelFeature

extension SweepTests {
    /// Lane 6: Cost and Accounts to the prototype (`cost.js`, `accounts.js`), each state beside its prototype shot.
    static func costShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let window = CGSize(width: 1400, height: 900)
        let tall = CGSize(width: 1400, height: 1700)
        func cost(_ setUp: @escaping (CompanyModel) -> Void = { _ in }) -> CitadelStore {
            stage(.cost, nil) {
                CompanyFixture.costParityPage($0)
                setUp($0)
            }
        }
        func accounts(_ setUp: @escaping (CompanyModel) -> Void = { _ in }) -> CitadelStore {
            let store = stage(.accounts, nil) {
                CompanyFixture.accountsParityPage($0)
                setUp($0)
            }
            for event in [
                try? CompanyFixture.fallbackEvent(
                    seq: 18_440, run: 424, from: "claude-work", to: "claude-personal", reason: "account at limit"),
                try? CompanyFixture.fallbackEvent(
                    seq: 18_441, run: 429, from: "gpt-5.5", to: "Opus 5.5", reason: "codex-pro 5 h at 100%"),
            ].compactMap({ $0 }) {
                store.received(event)
            }
            return store
        }
        return [
            ("l6-cost", cost(), window),
            ("l6-cost-full", cost(), tall),
            ("l6-cost-project-tab", cost { $0.costPage.breakdownTab = "project" }, tall),
            ("l6-cost-agent-tab", cost { $0.costPage.breakdownTab = "agent" }, tall),
            ("l6-cost-account-tab", cost { $0.costPage.breakdownTab = "account" }, tall),
            ("l6-cost-price", cost { $0.costPage.drawer = .price }, window),
            ("l6-cost-new-budget", cost { $0.costPage.drawer = .newBudget }, window),
            ("l6-accounts", accounts(), window),
            ("l6-accounts-full", accounts(), tall),
            ("l6-accounts-agents-tab", accounts { $0.accountsPage.chainsTab = "agents" }, tall),
            ("l6-accounts-pool", accounts { $0.accountsPage.showsWholePool = true }, window),
            ("l6-accounts-limits", accounts { $0.accountsPage.drawer = .limits(4) }, window),
            ("l6-accounts-relogin", accounts { $0.accountsPage.drawer = .relogin(5) }, window),
            ("l6-accounts-add", accounts { $0.accountsPage.drawer = .add }, window),
            (
                "l6-accounts-chain",
                accounts {
                    let id = $0.accountsPage.sharedChains(Array($0.agents.values)).first?.id ?? ""
                    $0.accountsPage.drawer = .chain(id)
                }, window
            ),
        ]
    }
}
