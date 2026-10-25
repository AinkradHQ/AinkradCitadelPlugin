import AinkradAppKit
import SwiftUI

/// The Board tab (`quest-board.js` `qBoard`): type / epic filters and grouping, the sprint line, then four columns.
/// Cards drag between columns (each drop is the state machine's step, WIP checked first, with Undo); a card opens
/// the item drawer.
struct ProjectBoard: View {
    let store: CitadelStore
    let facts: ProjectFacts
    @Environment(\.ainkradSkin) private var skin

    private var page: ProjectsPage { facts.page }

    var body: some View {
        let items = page.filter.apply(facts.work.boardItems)
        VStack(alignment: .leading, spacing: skin.size.s12) {
            WorkToolbar(facts: facts) {
                SegStrip(
                    options: [("none", "No grouping"), ("epic", "By epic"), ("agent", "By agent")],
                    selection: page.filter.group
                ) { page.filter.group = $0 }
            }
            if let active = facts.active { sprintLine(active) }
            ForEach(lanes(items), id: \.id) { lane in
                if let title = lane.title {
                    HStack(spacing: skin.size.s8) {
                        RoundedRectangle(cornerRadius: skin.size.s3).fill(lane.tint).frame(
                            width: skin.size.s10, height: skin.size.s10)
                        Text(title).citadelFont("t12", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                        Text("\(lane.items.count)").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    }
                    .padding(.top, skin.size.s6)
                }
                HStack(alignment: .top, spacing: skin.size.s12) {
                    ForEach(ProjectLogic.columns, id: \.self) { column in
                        BoardColumn(
                            store: store, facts: facts, column: column,
                            items: lane.items.filter { $0.column == column },
                            showsAdd: column == "todo")
                    }
                }
            }
        }
    }

    private struct Lane {
        var id: String
        var title: String?
        var tint: Color
        var items: [WorkItem]
    }

    private func lanes(_ items: [WorkItem]) -> [Lane] {
        switch page.filter.group {
        case "epic":
            return facts.work.epics.map { epic in
                Lane(
                    id: "e\(epic.id)", title: epic.title,
                    tint: ProjectLook.epicTint(epic.id, in: facts.work, skin: skin),
                    items: items.filter { $0.epicID == epic.id })
            } + [
                Lane(
                    id: "e-", title: "No epic", tint: skin.color(skin.text.faint),
                    items: items.filter { $0.epicID == nil })
            ]
        case "agent":
            var owners: [Int64?] = []
            for item in items where !owners.contains(item.ownerAgentID) { owners.append(item.ownerAgentID) }
            return owners.map { owner in
                Lane(
                    id: "a\(owner ?? 0)", title: owner.flatMap { facts.model.agents[$0]?.name } ?? "Unassigned",
                    tint: skin.color(skin.palette.accentPrimary), items: items.filter { $0.ownerAgentID == owner })
            }
        default:
            return [Lane(id: "all", title: nil, tint: .clear, items: items)]
        }
    }

    private func sprintLine(_ sprint: SprintDetail) -> some View {
        let cyan = skin.color(skin.palette.accentSecondary)
        let report = facts.report
        return HStack(spacing: skin.size.s12) {
            Text("Sprint \(sprint.name)").citadelFont("t12", weight: "bold").foregroundStyle(
                skin.color(skin.text.primary))
            Text(sprint.goal).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
            Spacer(minLength: skin.size.s8)
            if let day = sprint.day() {
                Text("day \(day.day) of \(day.of)").citadelFont("t11", mono: true).foregroundStyle(
                    skin.color(skin.text.faint))
            }
            if let report {
                ProgressTrack(value: report.fraction, tint: cyan).frame(width: skin.size.s140)
                Text("\(report.completed)/\(report.committed) pts").citadelFont("t11", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary))
            }
        }
        .padding(.horizontal, skin.size.s14).padding(.vertical, skin.size.s10)
        .background(cyan.opacity(skin.opacity.o06), in: RoundedRectangle(cornerRadius: skin.size.s12))
        .overlay(RoundedRectangle(cornerRadius: skin.size.s12).strokeBorder(cyan.opacity(skin.opacity.o20)))
    }
}

/// One status column (`.qcol`): a drop zone that washes blue while a card hovers over it.
private struct BoardColumn: View {
    let store: CitadelStore
    let facts: ProjectFacts
    let column: String
    let items: [WorkItem]
    let showsAdd: Bool
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let ranked = ProjectLogic.ranked(items)
        VStack(alignment: .leading, spacing: skin.size.s8) {
            HStack(spacing: skin.size.s8) {
                Circle().fill(ProjectLook.flowTint(ProjectLogic.flowState(column) ?? column, skin: skin))
                    .frame(width: skin.size.s8, height: skin.size.s8)
                Text(ProjectLogic.title(column)).citadelFont("t12_5", weight: "bold").foregroundStyle(
                    skin.color(skin.text.primary))
                Text("\(items.count)").citadelFont("t10", weight: "semibold", mono: true).foregroundStyle(
                    skin.color(skin.text.primary)
                )
                .padding(.horizontal, skin.size.s6).padding(.vertical, skin.size.s1)
                .background(
                    skin.color(.palette("foreground", skin.opacity.o07)),
                    in: RoundedRectangle(cornerRadius: skin.size.s5))
                Spacer(minLength: skin.size.s4)
                Text("\(items.reduce(0) { $0 + ($1.points ?? 0) }) pts").citadelFont("t11", mono: true)
                    .foregroundStyle(skin.color(skin.text.faint))
            }
            .padding(.horizontal, skin.size.s4).padding(.top, skin.size.s4)
            ForEach(ranked) { item in
                WorkCard(facts: facts, item: item) { store.openItem(item.id) }
                    .draggable(String(item.id)) { WorkCard(facts: facts, item: item) {}.frame(width: skin.size.s240) }
            }
            if showsAdd {
                DashedAdd(title: "＋ Add item") { store.newItem(project: facts.project.id) }
            }
        }
        .padding(.horizontal, skin.size.s8)
        .padding(.top, skin.size.s8)
        .padding(.bottom, skin.size.s10)
        .frame(maxWidth: .infinity, minHeight: skin.size.s120, alignment: .top)
        .ainkradDropZone { id in
            guard let id = Int64(id), let item = facts.work.items.first(where: { $0.id == id }) else { return false }
            store.moveItem(item, to: column, project: facts.project)
            return true
        }
    }
}

/// A work card (`.qc`): kind, key, ⚑, priority; title; epic; owner and points. Lifts on hover.
struct WorkCard: View {
    let facts: ProjectFacts
    let item: WorkItem
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        let epic = facts.work.epic(item.epicID)
        AinkradTapArea(action: open) {
            VStack(alignment: .leading, spacing: skin.size.s7) {
                HStack(spacing: skin.size.s6) {
                    ItemKindChip(kind: item.kind)
                    Text(item.key).citadelFont("t11", mono: true).foregroundStyle(
                        skin.color(skin.palette.accentSecondary))
                    Spacer(minLength: skin.size.s4)
                    if item.isBlocked {
                        Text("⚑").citadelFont("t11").foregroundStyle(skin.color(skin.palette.danger)).help("Blocked")
                    }
                    PriorityBars(level: item.level)
                }
                Text(item.title).citadelFont("t12_5", weight: "medium")
                    .foregroundStyle(skin.color(item.isDone ? skin.text.muted : skin.text.primary))
                    .strikethrough(item.isDone, color: skin.color(.palette("foreground", skin.opacity.o25)))
                    .lineSpacing(skin.size.s2).multilineTextAlignment(.leading)
                    .fixedSize(horizontal: false, vertical: true)
                if let epic {
                    EpicTag(title: epic.title, tint: ProjectLook.epicTint(epic.id, in: facts.work, skin: skin))
                }
                HStack {
                    if let agent = item.ownerAgentID.flatMap({ facts.model.agents[$0] }) {
                        AgentFigure(agent: agent, model: facts.model, size: skin.size.s20)
                    } else {
                        UnassignedDot()
                    }
                    Spacer()
                    PointsChip(points: item.points)
                }
            }
            .padding(.horizontal, skin.size.s11).padding(.vertical, skin.size.s10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(skin.color(.palette("background", skin.opacity.o95))))
            .overlay(
                shape.strokeBorder(
                    item.isBlocked
                        ? skin.color(skin.palette.danger).opacity(skin.opacity.o40)
                        : skin.color(.palette("foreground", hovering ? skin.opacity.o16 : skin.opacity.o08)))
            )
            .contentShape(shape)
        }
        .shadow(
            color: skin.color(.palette("black", hovering ? skin.opacity.o30 : skin.opacity.o20)),
            radius: hovering ? skin.size.s11 : skin.size.s3, y: hovering ? skin.size.s10 : skin.size.s2
        )
        .offset(y: hovering && !reduceMotion ? -skin.size.s2 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// The type and epic filters (`.q-bar`), with a trailing slot.
struct WorkToolbar<Trailing: View>: View {
    let facts: ProjectFacts
    @ViewBuilder let trailing: Trailing
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let page = facts.page
        AinkradFlowLayout(spacing: skin.size.s8, lineSpacing: skin.size.s8) {
            SegStrip(
                options: [("all", "All")]
                    + (facts.hasTrancheB
                    ? ["story", "task", "bug", "chore", "spike", "subtask"] : ["story", "task", "bug", "subtask"])
                    .map { ($0, ProjectLook.kind($0, skin: skin).title) },
                selection: page.filter.kind ?? "all", chip: { $0 == "all" ? nil : $0 }
            ) { page.filter.kind = $0 == "all" ? nil : $0 }
            if !facts.work.epics.isEmpty {
                SegStrip(
                    options: [("all", "All epics")] + facts.work.epics.map { ("\($0.id)", Self.cut($0.title, 18)) },
                    selection: page.filter.epic.map { "\($0)" } ?? "all",
                    dot: { id in Int64(id).map { ProjectLook.epicTint($0, in: facts.work, skin: skin) } }
                ) { page.filter.epic = Int64($0) }
            }
            trailing
        }
    }

    static func cut(_ text: String, _ length: Int) -> String {
        text.count > length ? String(text.prefix(length - 1)) + "…" : text
    }
}

/// A strip of small option chips (`.seg.q-seg .opt`): selected blue with an accent rim.
struct SegStrip: View {
    let options: [(id: String, title: String)]
    let selection: String
    var chip: (String) -> String? = { _ in nil }
    var dot: (String) -> Color? = { _ in nil }
    let pick: (String) -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s6) {
            ForEach(options, id: \.id) { option in
                SegOption(isOn: option.id == selection, action: { pick(option.id) }) {
                    if let kind = chip(option.id) { ItemKindChip(kind: kind, side: skin.size.s16) }
                    if let tint = dot(option.id) {
                        RoundedRectangle(cornerRadius: skin.size.s3).fill(tint).frame(
                            width: skin.size.s8, height: skin.size.s8)
                    }
                    Text(option.title)
                }
            }
        }
    }
}

/// One option chip (h28): blue .3 with an accent rim when on.
struct SegOption<Label: View>: View {
    let isOn: Bool
    let action: () -> Void
    @ViewBuilder let label: Label
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let blue = skin.color(skin.palette.accentPrimary)
        let shape = RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous)
        AinkradTapArea(action: action) {
            HStack(spacing: skin.size.s6) { label }
                .citadelFont("t11").foregroundStyle(skin.color(isOn ? .palette("foreground", 1) : skin.text.primary))
                .lineLimit(1)
                .padding(.horizontal, skin.size.s10).frame(height: skin.size.s28)
                .background(
                    shape.fill(
                        isOn
                            ? blue.opacity(skin.opacity.o30)
                            : skin.color(.palette("foreground", hovering ? skin.opacity.o08 : skin.opacity.o05)))
                )
                .overlay(
                    shape.strokeBorder(
                        isOn ? blue.opacity(skin.opacity.o60) : skin.color(.palette("foreground", skin.opacity.o08))))
        }
        .onHover { hovering = $0 }
    }
}

/// A dashed "＋ Add item" tile; the rim turns blue on hover.
struct DashedAdd: View {
    let title: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(action: action) {
            Text(title).citadelFont("t12").foregroundStyle(skin.color(hovering ? skin.text.primary : skin.text.faint))
                .frame(maxWidth: .infinity).padding(skin.size.s8)
                .overlay(
                    RoundedRectangle(cornerRadius: skin.size.s10).strokeBorder(
                        hovering
                            ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o45)
                            : skin.color(.palette("foreground", skin.opacity.o12)),
                        style: StrokeStyle(lineWidth: 1, dash: [skin.size.s4, skin.size.s3]))
                )
                .contentShape(Rectangle())
        }
        .onHover { hovering = $0 }
    }
}

/// A thin progress track (`.bar`).
struct ProgressTrack: View {
    let value: Double
    let tint: Color
    var height: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let side = height ?? skin.size.s6
        GeometryReader { geo in
            ZStack(alignment: .leading) {
                Capsule().fill(skin.color(.palette("foreground", skin.opacity.o08)))
                Capsule().fill(tint).frame(width: geo.size.width * min(max(value, 0), 1))
            }
        }
        .frame(height: side)
    }
}
