import AinkradAppKit
import CitadelClient
import Foundation

/// The work-item drawer's own fields (API minor 18): title, description, type, 5-level priority and acceptance
/// criteria, each one `PATCH /issues/{id}`. Shown at once, put back when the server refuses; an older server gets
/// no write (the drawer shows the fields read-only).
extension CitadelStore {
    /// Whether the server speaks API minor 18 (tranche B): issue edits, epics, project identity and the rest.
    var hasTrancheB: Bool { serverSupports(minor: Self.trancheBMinor) }

    func setTitle(_ item: WorkItem, _ title: String, project: Int64) {
        let title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !title.isEmpty, title != item.title else { return }
        edit(item, project: project, saved: "title", patch: .init(title: title)) { $0.title = title }
    }

    func setBody(_ item: WorkItem, _ body: String, project: Int64) {
        guard body != item.body else { return }
        edit(item, project: project, saved: "description", patch: .init(body: body)) { $0.body = body }
    }

    func setKind(_ item: WorkItem, _ kind: String, project: Int64) {
        guard kind != item.kind else { return }
        let word = Schemas.IssueKind(value1: .init(rawValue: kind), value2: kind)
        edit(item, project: project, saved: "type", patch: .init(kind: word)) { $0.kind = kind }
    }

    func setPriority(_ item: WorkItem, level: String, project: Int64) {
        guard level != item.priorityLevel else { return }
        let word = Schemas.PriorityLevel(value1: .init(rawValue: level), value2: level)
        edit(item, project: project, saved: "priority", patch: .init(priorityLevel: word)) {
            $0.priorityLevel = level
            $0.priority = level == "high" || level == "urgent"
        }
    }

    /// The whole list goes back, in order (the server replaces it).
    func setCriteria(_ item: WorkItem, _ criteria: [CriterionInfo], project: Int64) {
        guard criteria != item.criteria else { return }
        let sent = criteria.map { Schemas.Criterion(done: $0.done, text: $0.text) }
        edit(item, project: project, saved: "criteria", patch: .init(criteria: sent)) { $0.criteria = criteria }
    }

    private func edit(
        _ item: WorkItem, project: Int64, saved: String, patch: Schemas.IssuePatch,
        _ change: @escaping (inout WorkItem) -> Void
    ) {
        guard hasTrancheB, let server, let model else { return }
        update(item.id, in: project, change)
        Task {
            switch await server.updateIssue(item.id, patch) {
            case .success(let fresh):
                if let index = model.projectsPage.work[project]?.items.firstIndex(where: { $0.id == item.id }) {
                    model.projectsPage.work[project]?.items[index] = fresh
                }
                if let activity = await activity(of: item.id, server: server) {
                    model.projectsPage.itemActivity[item.id] = activity
                }
            case .failure(let answer):
                update(item.id, in: project) { $0 = item }
                toast(
                    AinkradRichToast(
                        title: "Couldn't save \(item.key)'s \(saved)", body: answer.message, status: .danger))
            }
        }
    }
}

/// Epics (API minor 18): colour, dates and the requirement they serve, one `PATCH /epics/{id}`.
extension CitadelStore {
    /// `nil` leaves a field as it is; a gated older server is sent nothing.
    func editEpic(
        _ epic: EpicInfo, project: Int64, color: String? = nil, startsOn: String? = nil, endsOn: String? = nil,
        requirement: Int64? = nil
    ) {
        guard hasTrancheB, let server, let model else { return }
        let patch = Schemas.EpicPatch(
            color: color, endsOn: endsOn, requirementId: requirement, startsOn: startsOn)
        Task {
            switch await server.updateEpic(epic.id, patch) {
            case .success(let fresh):
                if let index = model.projectsPage.work[project]?.epics.firstIndex(where: { $0.id == epic.id }) {
                    model.projectsPage.work[project]?.epics[index] = fresh
                }
            case .failure(let answer):
                toast(
                    AinkradRichToast(
                        title: "Couldn't change \(epic.key)", body: answer.message, status: .danger))
            }
        }
    }
}
