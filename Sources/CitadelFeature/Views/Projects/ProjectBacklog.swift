import AinkradAppKit
import SwiftUI

/// The Backlog tab (`quest-board.js` `qBacklog`): the active sprint, the planned one (capacity bar, Start), then the
/// backlog in rank order. Rows drag between sections (sprint in / out, with Undo); a drop on a row puts the dragged
/// one before it (`POST /issues/{id}/move`).
struct ProjectBacklog: View {
    let store: CitadelStore
    let facts: ProjectFacts
    @State private var confirmsStart = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let work = facts.work
        let items = facts.page.filter.apply(work.items.filter { $0.state != "cancelled" })
        let active = work.active
        let next = work.next
        let backlog = ProjectLogic.ranked(
            items.filter { $0.isOpen && ($0.sprintID == nil || ($0.sprintID != active?.id && $0.sprintID != next?.id)) }
        )
        VStack(alignment: .leading, spacing: skin.size.s12) {
            WorkToolbar(facts: facts) {
                AinkradButton(title: "＋ New item", style: .secondary) { store.newItem(project: facts.project.id) }
                    .compact().fixedSize()
            }
            if let active {
                let mine = ProjectLogic.ranked(items.filter { $0.sprintID == active.id })
                BacklogSection(
                    store: store, facts: facts, title: "Sprint \(active.name) · active",
                    subtitle: "\(active.goal.isEmpty ? "" : active.goal + " · ")\(points(mine)) pts", items: mine,
                    sprint: active
                ) {
                    if let day = active.day() {
                        Text("day \(day.day)/\(day.of)").citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.text.faint))
                    }
                }
            }
            if let next {
                let mine = ProjectLogic.ranked(items.filter { $0.sprintID == next.id })
                BacklogSection(
                    store: store, facts: facts, title: "Sprint \(next.name) · planning",
                    subtitle: "\(next.goal.isEmpty ? "" : next.goal + " · ")\(next.range)", items: mine, sprint: next
                ) {
                    capacity(points(mine))
                    AinkradButton(title: "Start \(next.name)", style: .primary) { confirmsStart = true }.compact()
                        .fixedSize()
                }
            }
            BacklogSection(
                store: store, facts: facts, title: "Backlog",
                subtitle: "\(backlog.count) items · \(points(backlog)) pts · ordered by rank",
                items: backlog, sprint: nil
            ) { EmptyView() }
        }
        .ainkradConfirmDialog(
            isPresented: $confirmsStart, title: "Start sprint \(next?.name ?? "")?",
            message:
                "\(active.map { "\($0.name) closes; its unfinished items move to \(next?.name ?? "the next sprint"). " } ?? "")The lead hands out the first issues and the burndown starts today.",
            confirmTitle: "Start \(next?.name ?? "")"
        ) { store.startNextSprint(project: facts.project.id) }
    }

    private func points(_ items: [WorkItem]) -> Int { items.reduce(0) { $0 + ($1.points ?? 0) } }

    /// The team's capacity for a sprint: every member's but the PO's and lead's (`getTeamCapacity`).
    @ViewBuilder private func capacity(_ planned: Int) -> some View {
        let seats = facts.team?.seats.filter { !["product_owner", "team_lead"].contains($0.teamRole) } ?? []
        let cap = seats.compactMap { facts.work.capacity[$0.agentID] }.reduce(0, +)
        if cap > 0 {
            HStack(spacing: skin.size.s8) {
                ProgressTrack(
                    value: Double(planned) / Double(cap),
                    tint: planned > cap ? skin.color(skin.palette.warning) : skin.color(skin.palette.accentSecondary)
                )
                .frame(width: skin.size.s120)
                Text("\(planned) / \(cap) pts capacity").citadelFont("t11", mono: true).foregroundStyle(
                    skin.color(skin.text.primary))
            }
        }
    }
}

/// One section (`.qsec`): header, rows, "Drag items here" when empty; a drop zone for its sprint.
private struct BacklogSection<Extra: View>: View {
    let store: CitadelStore
    let facts: ProjectFacts
    let title: String
    let subtitle: String
    let items: [WorkItem]
    let sprint: SprintDetail?
    @ViewBuilder let extra: Extra
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: skin.size.s10) {
                Text(title).citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                Text(subtitle).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                Spacer(minLength: skin.size.s8)
                extra
            }
            .padding(.horizontal, skin.size.s14).padding(.vertical, skin.size.s12)
            VStack(spacing: 0) {
                ForEach(items) { item in
                    BacklogRow(facts: facts, item: item) { store.openItem(item.id) }
                        .draggable(String(item.id)) {
                            BacklogRow(facts: facts, item: item) {}.frame(width: skin.size.s480)
                        }
                        .dropDestination(for: String.self) { ids, _ in drop(ids.first, before: item) }
                }
                if items.isEmpty {
                    Text("Drag items here").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                        .frame(maxWidth: .infinity).padding(skin.size.s14)
                        .overlay(
                            RoundedRectangle(cornerRadius: skin.size.s10).strokeBorder(
                                skin.color(.palette("foreground", skin.opacity.o10)),
                                style: StrokeStyle(lineWidth: 1, dash: [skin.size.s4, skin.size.s3]))
                        )
                        .padding(.horizontal, skin.size.s6).padding(.bottom, skin.size.s4)
                }
            }
            .padding(.horizontal, skin.size.s6).padding(.bottom, skin.size.s8)
        }
        .ainkradDropZone { drop($0, before: nil) }
    }

    /// Into this section; dropped on a row of the same section, a new rank before it.
    private func drop(_ id: String?, before row: WorkItem?) -> Bool {
        guard let id = id.flatMap(Int64.init), let item = facts.work.items.first(where: { $0.id == id }) else {
            return false
        }
        if items.contains(where: { $0.id == id }) {
            guard let row, row.id != id, let at = items.firstIndex(where: { $0.id == row.id }),
                let place = ProjectLogic.place(id, at: at, in: items)
            else { return false }
            store.rank(item, place, project: facts.project.id)
        } else {
            store.setSprint(item, to: sprint, project: facts.project.id)
        }
        return true
    }
}

/// A backlog row (`.qr`): grip, kind, key, title, epic, ⚑, priority, state, owner, points.
private struct BacklogRow: View {
    let facts: ProjectFacts
    let item: WorkItem
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let epic = facts.work.epic(item.epicID)
        AinkradTapArea(action: open) {
            HStack(spacing: skin.size.s8) {
                Text("⋮⋮").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).help("Drag to move")
                ItemKindChip(kind: item.kind)
                Text(item.key).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.palette.accentSecondary))
                Text(item.title).citadelFont("t12_5")
                    .foregroundStyle(skin.color(item.isDone ? skin.text.muted : skin.text.primary))
                    .strikethrough(item.isDone).lineLimit(1)
                if let epic {
                    EpicTag(title: epic.title, tint: ProjectLook.epicTint(epic.id, in: facts.work, skin: skin))
                        .frame(maxWidth: skin.size.s220, alignment: .leading).fixedSize()
                }
                Spacer(minLength: skin.size.s8)
                if item.isBlocked { Text("⚑").citadelFont("t11").foregroundStyle(skin.color(skin.palette.danger)) }
                PriorityBars(high: item.priority)
                StateTag(state: item.state == "blocked" ? "in_progress" : item.state)
                if let agent = item.ownerAgentID.flatMap({ facts.model.agents[$0] }) {
                    AgentFigure(agent: agent, model: facts.model, size: skin.size.s20)
                } else {
                    UnassignedDot()
                }
                PointsChip(points: item.points)
            }
            .padding(.horizontal, skin.size.s8)
            .frame(height: skin.size.s40)
            .background(
                skin.color(.palette("foreground", hovering ? skin.opacity.o05 : 0)),
                in: RoundedRectangle(cornerRadius: skin.size.s10)
            )
            .contentShape(Rectangle())
        }
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}
