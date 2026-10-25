import Foundation
import SwiftUI

@testable import CitadelFeature

extension SweepTests {
    /// Screens 14 Project profile and 16 Limits, at the mockups' window sizes.
    static func settingsShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let window = CGSize(width: 1400, height: 900)
        func settings(_ section: CompanySettingsSection, _ extra: @escaping (CompanyModel) -> Void = { _ in })
            -> CitadelStore
        {
            let store = stage(.home, nil) {
                CompanyFixture.companySettingsPage($0, section: section)
                extra($0)
            }
            store.isShowingSettings = true
            return store
        }
        let limits = stage(.home, nil, CompanyFixture.limitsPage)
        limits.isShowingSettings = true
        return [
            ("17-settings-general", settings(.general), window),
            ("17-settings-members", settings(.devices), window),
            ("17-settings-accounts", settings(.accounts), window),
            ("17-settings-limits", settings(.limits), window),
            ("17-settings-limits-full", settings(.limits), CGSize(width: 1400, height: 2000)),
            ("17-settings-notifications", settings(.notifications), window),
            ("17-settings-skills", settings(.skills), window),
            ("17-settings-audit", settings(.audit), window),
            ("17-settings-audit-agents", settings(.audit) { $0.limitsPage.auditActor = "agents" }, window),
            (
                "14-project-settings", stage(.projects, nil, CompanyFixture.projectsPage),
                CGSize(width: 1280, height: 1700)
            ),
            ("14-project-new", stage(.projects, nil, CompanyFixture.projectsPage), CGSize(width: 1280, height: 900)),
            (
                "14-profile-history", stage(.projects, nil, CompanyFixture.profileHistory),
                CGSize(width: 1280, height: 900)
            ),
            (
                "14-proposal-reject", stage(.projects, nil, CompanyFixture.projectsPage),
                CGSize(width: 1280, height: 900)
            ),
            ("16-limits", limits, CGSize(width: 1280, height: 1290)),
        ]
    }

    /// The sheet a shot shows over its screen: the ones opened by a click (＋, History →, Reject…, ⋯).
    @MainActor static func sheet(_ name: String, _ store: CitadelStore) -> AnyView? {
        guard let model = store.model, let project = model.projects.first else { return nil }
        switch name {
        case "14-project-new": return AnyView(NewProjectSheet(store: store, isPresented: .constant(true)))
        case "14-profile-history":
            return AnyView(ProfileHistorySheet(model: model, project: project, isPresented: .constant(true)))
        case "14-proposal-reject":
            return AnyView(
                PromptSheet(
                    title: "Reject Lint command?",
                    message: "The profile stays as it is. A reason is optional; the agent sees it.",
                    placeholder: "Why not (optional)", confirmTitle: "Reject", isDestructive: true,
                    allowsEmpty: true, text: "", isPresented: .constant(true)
                ) { _ in })
        case "12-requirement-cancel":
            return AnyView(
                PromptSheet(
                    title: "Cancel R-12?",
                    message:
                        "Its open issues are cancelled with it. Citadel refuses while a run works on one — stop the run first.",
                    placeholder: "Why (optional)", confirmTitle: "Cancel requirement", isDestructive: true,
                    allowsEmpty: true, text: "", isPresented: .constant(true)
                ) { _ in })
        default: return nil
        }
    }
}
