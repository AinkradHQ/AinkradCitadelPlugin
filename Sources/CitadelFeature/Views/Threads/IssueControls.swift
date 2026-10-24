import AinkradAppKit
import SwiftUI

/// Under an agent thread's title: what blocks the issue (unlink ×, link one, block on one — API minor 14), and its
/// sprint (join a planned or the active one — an active sprint's scope change, minor 12 — leave it, or delete an
/// empty planned sprint, minor 13).
struct IssueControls: View {
    let store: CitadelStore
    let model: CompanyModel
    let issue: IssueInfo
    @Environment(\.ainkradSkin) private var skin

    private var blockers: [IssueInfo] { model.blockers[issue.id] ?? [] }
    private var sprints: [ProjectSprintInfo] { model.projectSprints[issue.projectID] ?? [] }

    /// Issues of the project that could block this one: open, not itself, not already linked.
    private var candidates: [IssueInfo] {
        let linked = Set(blockers.map(\.id))
        return (model.projectIssues[issue.projectID] ?? [])
            .filter { $0.id != issue.id && !linked.contains($0.id) && !["done", "cancelled"].contains($0.state) }
            .sorted { $0.id > $1.id }
    }

    var body: some View {
        HStack(spacing: skin.size.s8) {
            Text("Blocked by").citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
            if blockers.isEmpty {
                Text("nothing").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
            ForEach(blockers) { blocker in
                AinkradChip(label: "\(blocker.key) · \(blocker.state.replacingOccurrences(of: "_", with: " "))") {
                    store.unlinkBlocker(issue, blocker: blocker)
                }
                .ainkradTooltip("\(blocker.title) — unlink it")
            }
            if !candidates.isEmpty {
                AinkradMenuButton(
                    items: candidates.prefix(40).map { other in
                        AinkradMenuItem(title: "\(other.key) \(other.title)", systemName: nil) {
                            store.linkBlocker(issue, blocker: other)
                        }
                    }
                ) { Text("Link blocker…") }
            }
            if issue.state != "blocked", !(blockers.isEmpty && candidates.isEmpty) {
                AinkradMenuButton(
                    items: (blockers + candidates).prefix(40).map { other in
                        AinkradMenuItem(title: "\(other.key) \(other.title)", systemName: nil) {
                            store.block(issue, on: other)
                        }
                    }
                ) { Text("Block on…") }
            }
            Spacer(minLength: skin.size.s8)
            if !sprints.isEmpty { sprintMenu }
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.bottom, skin.size.s8)
    }

    /// "Sprint: WRK Sprint 2 ▾" — join a planned or the active sprint, leave it, or delete an empty planned one.
    private var sprintMenu: some View {
        let current = sprints.first { $0.id == issue.sprintID }
        let open = sprints.filter { ["planned", "active"].contains($0.state) }
        var items: [AinkradMenuItem] = open.filter { $0.id != issue.sprintID }.map { sprint in
            let scope = sprint.state == "active" ? " (scope change)" : ""
            return AinkradMenuItem(title: "Move to \(sprint.name)\(scope)", systemName: nil) {
                store.setSprint(issue, to: sprint)
            }
        }
        if let current, current.state != "closed" {
            items.append(
                AinkradMenuItem(title: "Take out of \(current.name)", systemName: nil) {
                    store.setSprint(issue, to: nil)
                })
        }
        items += open.filter { $0.state == "planned" && isEmpty($0) }.map { sprint in
            AinkradMenuItem(title: "Delete empty \(sprint.name)", systemName: nil) {
                store.deleteSprint(sprint, of: issue)
            }
        }
        return AinkradMenuButton(items: items) { Text("Sprint: \(current?.name ?? "none")") }
            .disabled(items.isEmpty)
    }

    /// No issue of the project is in it (as far as the project's issue list says).
    private func isEmpty(_ sprint: ProjectSprintInfo) -> Bool {
        !(model.projectIssues[issue.projectID] ?? []).contains { $0.sprintID == sprint.id }
    }
}
