import AinkradAppKit
import SwiftUI

/// The work-item drawer's editable fields (API minor 18): title, type, 5-level priority, description and acceptance
/// criteria. On an older server each is shown read-only, as before.

/// The title, edited in place; Return saves it.
struct ProjectsItemTitle: View {
    let store: CitadelStore
    let item: WorkItem
    let project: Int64
    @State private var draft = ""
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        if store.hasTrancheB {
            AinkradTextField(text: $draft, placeholder: "Title").onSubmit {
                store.setTitle(item, draft, project: project)
            }
            .onAppear { draft = item.title }
            .onChange(of: item.title) { _, new in draft = new }
        } else {
            Text(item.title).citadelFont("t20", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// The Type row: story, task, bug, chore, spike (and subtask when it is one).
struct ProjectsItemKindRow: View {
    let store: CitadelStore
    let item: WorkItem
    let project: Int64
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let kinds = ["story", "task", "bug", "chore", "spike"] + (item.kind == "subtask" ? ["subtask"] : [])
        AinkradFlowLayout(spacing: skin.size.s6) {
            ForEach(kinds, id: \.self) { kind in
                SegOption(isOn: item.kind == kind) {
                    store.setKind(item, kind, project: project)
                } label: {
                    ItemKindChip(kind: kind, side: skin.size.s16)
                    Text(ProjectLook.kind(kind, skin: skin).title)
                }
            }
        }
    }
}

/// The Priority row: the five levels, each with its bars; an older server shows its one flag.
struct ProjectsItemPriorityRow: View {
    let store: CitadelStore
    let item: WorkItem
    let project: Int64
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        if store.hasTrancheB {
            AinkradFlowLayout(spacing: skin.size.s6) {
                ForEach(PriorityBars.levels.reversed(), id: \.self) { level in
                    SegOption(isOn: item.level == level) {
                        store.setPriority(item, level: level, project: project)
                    } label: {
                        PriorityBars(level: level)
                        Text(PriorityBars.title(level))
                    }
                }
            }
        } else {
            HStack(spacing: skin.size.s8) {
                PriorityBars(high: item.priority)
                Text(item.priority ? "High" : "Normal").citadelFont("t12").foregroundStyle(
                    skin.color(skin.text.primary))
                if !item.priority {
                    AinkradButton(title: "Raise to High", style: .ghost) { store.prioritize(item, project: project) }
                        .borderless().secondaryAccent().compact().fixedSize()
                }
            }
        }
    }
}

/// The description (`.h-editor`): read-only on an older server, else an editor with Save and Revert once changed.
struct ProjectsItemDescription: View {
    let store: CitadelStore
    let item: WorkItem
    let project: Int64
    @State private var draft = ""
    @Environment(\.ainkradSkin) private var skin

    private var isDirty: Bool { draft != item.body }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                Text("¶ Description").citadelFont("t11", weight: "semibold").foregroundStyle(
                    skin.color(skin.text.muted))
                Spacer()
                if store.hasTrancheB && isDirty {
                    AinkradButton(title: "Revert", style: .ghost) { draft = item.body }.borderless().compact()
                        .fixedSize()
                    AinkradButton(title: "Save", style: .secondary) { store.setBody(item, draft, project: project) }
                        .compact().fixedSize()
                } else {
                    Text("agents read this first").citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                }
            }
            .padding(.horizontal, skin.size.s12).frame(height: skin.size.s36)
            .background(skin.color(.palette("foreground", skin.opacity.o05)))
            if store.hasTrancheB {
                AinkradTextArea(
                    text: $draft, placeholder: "What should the agent know before it starts?", minHeight: skin.size.s90
                )
                .onAppear { draft = item.body }
                .onChange(of: item.body) { _, new in draft = new }
                .padding(skin.size.s6)
            } else {
                Text(item.body.isEmpty ? "No description yet." : item.body).citadelFont("t12_5", mono: true)
                    .foregroundStyle(skin.color(item.body.isEmpty ? skin.text.faint : skin.text.primary))
                    .frame(maxWidth: .infinity, minHeight: skin.size.s90, alignment: .topLeading).padding(skin.size.s12)
            }
        }
        .background(skin.color(.palette("black", skin.opacity.o28)))
        .clipShape(RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous))
    }
}

/// Acceptance criteria: a toggle card per criterion and an add row. Hidden on an older server (it stores none).
struct ProjectsItemCriteria: View {
    let store: CitadelStore
    let item: WorkItem
    let project: Int64
    @State private var draft = ""
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        if store.hasTrancheB {
            VStack(alignment: .leading, spacing: skin.size.s6) {
                TileHead(title: "Acceptance criteria · \(item.criteria.filter(\.done).count)/\(item.criteria.count)")
                AinkradCardGrid(columns: 1, spacing: skin.size.s6) {
                    ForEach(Array(item.criteria.enumerated()), id: \.offset) { index, criterion in
                        AinkradToggleCard(title: criterion.text, isOn: criterion.done) {
                            var all = item.criteria
                            all[index].done.toggle()
                            store.setCriteria(item, all, project: project)
                        }
                    }
                    AinkradChoiceCard(isAdd: true, minHeight: skin.size.s46) {
                        AinkradTextField(text: $draft, placeholder: "Add a criterion — e.g. Retries are capped")
                            .compact()
                            .onSubmit(add)
                        AinkradButton(title: "Add", style: .secondary) { add() }.compact().fixedSize()
                    }
                }
            }
        }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        draft = ""
        store.setCriteria(item, item.criteria + [CriterionInfo(text: text)], project: project)
    }
}
