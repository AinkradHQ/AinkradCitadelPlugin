import Foundation
import SwiftUI

@testable import CitadelFeature

extension SweepTests {
    /// Screen 14 Projects: the list, the project page's tabs, the item drawer and the configuration drawer.
    static func projectsShots(_ stage: SweepStage) -> [(String, CitadelStore, CGSize)] {
        let size = CGSize(width: 1440, height: 900)
        var shots: [(String, CitadelStore, CGSize)] = [
            ("14p-list", stage(.projects, nil, CompanyFixture.projectWorkPage), size)
        ]
        for tab in ProjectTab.allCases {
            shots.append(("14p-\(tab.rawValue)", stage(.projects, nil, CompanyFixture.projectPage(tab: tab)), size))
        }
        shots.append(
            ("14p-item", stage(.projects, nil, CompanyFixture.projectPage(tab: .board, drawer: .item(42))), size))
        for tab in ConfigTab.allCases {
            shots.append(
                (
                    "14p-config-\(tab.rawValue)",
                    stage(.projects, nil, CompanyFixture.projectPage(tab: .overview, drawer: .config(tab))), size
                ))
        }
        return shots
    }
}
