import AinkradAppKit
import SwiftUI

/// The work-item drawer (`quest-item.js`): status steps, the live strip, the fields (assignee, estimate, sprint,
/// epic), the description, the acceptance criteria, the runs, the activity and a comment box. From API minor 18
/// the title, description, type, 5-level priority and criteria are edited here (`PATCH /issues/{id}`); an older
/// server shows them read-only.
struct WorkItemPanel: View {
    let store: CitadelStore
    let facts: ProjectFacts
    let itemID: Int64
    @State private var comment = ""
    @Environment(\.ainkradSkin) private var skin

    private var page: ProjectsPage { facts.page }

    var body: some View {
        if let item = facts.work.items.first(where: { $0.id == itemID }) {
            VStack(alignment: .leading, spacing: skin.size.s14) {
                top(item)
                ProjectsItemTitle(store: store, item: item, project: facts.project.id)
                steps(item)
                if let run = item.checkoutRunID { live(item, run: run) }
                fields(item)
                ProjectsItemDescription(store: store, item: item, project: facts.project.id)
                ProjectsItemCriteria(store: store, item: item, project: facts.project.id)
                runs(item)
                activity(item)
            }
        } else {
            AinkradEmptyState(icon: "tray", title: "Item not found", message: "It may have been moved or removed.")
        }
    }

    private func top(_ item: WorkItem) -> some View {
        HStack(spacing: skin.size.s8) {
            ItemKindChip(kind: item.kind)
            Text(item.key).citadelFont("t12", mono: true).foregroundStyle(skin.color(skin.palette.accentSecondary))
            if let epic = facts.work.epic(item.epicID) {
                EpicTag(title: epic.title, tint: ProjectLook.epicTint(epic.id, in: facts.work, skin: skin))
            }
            Spacer(minLength: skin.size.s8)
            if item.isBlocked {
                Text("⚑ Blocked").citadelFont("t11").foregroundStyle(skin.color(skin.palette.danger))
                    .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
                    .background(
                        skin.color(skin.palette.danger).opacity(skin.opacity.o12),
                        in: RoundedRectangle(cornerRadius: skin.size.s6))
            }
            StateTag(state: item.state)
        }
    }

    /// Four equal cells; the current one glows in its colour. Click sets the status through the state machine.
    private func steps(_ item: WorkItem) -> some View {
        let current = ProjectLogic.columns.firstIndex(of: item.column) ?? 0
        return HStack(spacing: skin.size.s6) {
            ForEach(Array(ProjectLogic.columns.enumerated()), id: \.offset) { index, column in
                let tint = ProjectLook.flowTint(ProjectLogic.flowState(column) ?? column, skin: skin)
                let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
                AinkradTapArea(help: "Set status to \(ProjectLogic.title(column))") {
                    store.moveItem(item, to: column, project: facts.project)
                } label: {
                    HStack(spacing: skin.size.s6) {
                        Circle().fill(index <= current ? tint : skin.color(.palette("foreground", skin.opacity.o25)))
                            .frame(width: skin.size.s8, height: skin.size.s8)
                            .shadow(color: tint.opacity(index == current ? skin.opacity.o60 : 0), radius: skin.size.s4)
                        Text(ProjectLogic.title(column)).citadelFont("t12")
                            .foregroundStyle(
                                index == current ? skin.color(.palette("foreground", 1)) : skin.color(skin.text.muted))
                    }
                    .frame(maxWidth: .infinity, minHeight: skin.size.s34)
                    .background(
                        shape.fill(
                            index == current
                                ? tint.opacity(skin.opacity.o16) : skin.color(.palette("foreground", skin.opacity.o05)))
                    )
                    .overlay(
                        shape.strokeBorder(
                            index == current
                                ? tint.opacity(skin.opacity.o60) : skin.color(.palette("foreground", skin.opacity.o07)))
                    )
                }
            }
        }
    }

    private func live(_ item: WorkItem, run: Int64) -> some View {
        let cyan = skin.color(skin.palette.accentSecondary)
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        let agent = item.ownerAgentID.flatMap { facts.model.agents[$0] }
        return HStack(spacing: skin.size.s8) {
            Circle().fill(cyan).frame(width: skin.size.s8, height: skin.size.s8)
            Text("\(agent?.name ?? "An agent") is working on it").citadelFont("t12").foregroundStyle(
                skin.color(skin.text.primary))
            Spacer(minLength: skin.size.s8)
            AinkradButton(title: "Open run →", style: .ghost) { store.open(.run(run)) }.borderless().secondaryAccent()
                .compact().fixedSize()
        }
        .padding(.horizontal, skin.size.s12).padding(.vertical, skin.size.s8)
        .background(shape.fill(cyan.opacity(skin.opacity.o07)))
        .overlay(shape.strokeBorder(cyan.opacity(skin.opacity.o25)))
    }

    private func fields(_ item: WorkItem) -> some View {
        let project = facts.project.id
        return VStack(alignment: .leading, spacing: skin.size.s12) {
            field("Assignee") {
                HStack(spacing: skin.size.s8) {
                    ForEach(facts.agents) { agent in
                        AinkradTapArea(help: agent.name) {
                            store.assign(item, to: agent.id, project: project)
                        } label: {
                            AgentFigure(agent: agent, model: facts.model, size: skin.size.s34)
                                .padding(skin.size.s2)
                                .overlay(
                                    Circle().strokeBorder(
                                        skin.color(skin.palette.accentPrimary),
                                        lineWidth: item.ownerAgentID == agent.id ? skin.size.s2 : 0))
                        }
                    }
                    if facts.agents.isEmpty {
                        Text("No team on this project").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                    }
                }
            }
            field("Priority") { ProjectsItemPriorityRow(store: store, item: item, project: project) }
            if store.hasTrancheB { field("Type") { ProjectsItemKindRow(store: store, item: item, project: project) } }
            field("Estimate") {
                HStack(spacing: skin.size.s6) {
                    ForEach([1, 2, 3, 5, 8, 13], id: \.self) { points in
                        SegOption(isOn: item.points == points) {
                            store.estimate(item, points: points, project: project)
                        } label: {
                            Text("\(points)")
                        }
                    }
                }
            }
            field("Sprint") {
                HStack(spacing: skin.size.s6) {
                    SegOption(isOn: item.sprintID == nil) {
                        store.setSprint(item, to: nil, project: project)
                    } label: {
                        Text("Backlog")
                    }
                    ForEach(facts.work.sprints.filter { $0.state != "closed" }) { sprint in
                        SegOption(isOn: item.sprintID == sprint.id) {
                            store.setSprint(item, to: sprint, project: project)
                        } label: {
                            Text("\(sprint.name) · \(sprint.state)")
                        }
                    }
                }
            }
            field("Epic") {
                AinkradFlowLayout(spacing: skin.size.s6) {
                    SegOption(isOn: item.epicID == nil) {
                        store.setEpic(item, epic: nil, project: project)
                    } label: {
                        Text("None")
                    }
                    ForEach(facts.work.epics) { epic in
                        SegOption(isOn: item.epicID == epic.id) {
                            store.setEpic(item, epic: epic.id, project: project)
                        } label: {
                            RoundedRectangle(cornerRadius: skin.size.s3).fill(
                                ProjectLook.epicTint(epic.id, in: facts.work, skin: skin)
                            )
                            .frame(width: skin.size.s8, height: skin.size.s8)
                            Text(String(epic.title.prefix(22)))
                        }
                    }
                }
            }
        }
        .padding(skin.size.s14)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)),
            in: RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous).strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o06))))
    }

    private func field<Content: View>(_ label: String, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(alignment: .center, spacing: skin.size.s10) {
            Text(label).citadelFont("t11_5").foregroundStyle(skin.color(skin.text.faint)).frame(
                width: skin.size.s90, alignment: .leading)
            content()
            Spacer(minLength: 0)
        }
    }

    private func runs(_ item: WorkItem) -> some View {
        let runs = page.itemRuns[item.id] ?? []
        return VStack(alignment: .leading, spacing: skin.size.s6) {
            TileHead(title: "Runs · \(runs.count)")
            if runs.isEmpty {
                Text("No runs yet — assign it and the agent wakes.").citadelFont("t12").foregroundStyle(
                    skin.color(skin.text.faint))
            }
            ForEach(runs) { run in
                AinkradTapArea(help: "Open run") {
                    store.open(.run(run.id))
                } label: {
                    HStack(spacing: skin.size.s8) {
                        if let agent = facts.model.agents[run.agentID] {
                            AgentFigure(agent: agent, model: facts.model, size: skin.size.s20)
                        }
                        Text("#\(run.id)").citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.palette.accentSecondary))
                        AinkradStatePill(
                            text: run.state.replacingOccurrences(of: "_", with: " "),
                            tint: skin.color(run.state == "failed" ? skin.palette.danger : skin.palette.accentSecondary)
                        )
                        Spacer(minLength: skin.size.s8)
                        Text(run.costMicros.map { String(format: "$%.2f", Double($0) / 1_000_000) } ?? "unpriced")
                            .citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    }
                    .frame(minHeight: skin.size.s30)
                }
            }
        }
    }

    private func activity(_ item: WorkItem) -> some View {
        let lines = page.itemActivity[item.id] ?? []
        return VStack(alignment: .leading, spacing: skin.size.s6) {
            TileHead(title: "Activity")
            ForEach(lines) { line in
                HStack(spacing: skin.size.s8) {
                    Text(
                        "\(who(line.actor)) \(line.action.replacingOccurrences(of: "_", with: " ").replacingOccurrences(of: ".", with: " "))"
                    )
                    .citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                    Spacer(minLength: skin.size.s8)
                    Text(line.at.formatted(.relative(presentation: .named))).citadelFont("t10_5").foregroundStyle(
                        skin.color(skin.text.faint))
                }
                .frame(minHeight: skin.size.s30)
            }
            HStack(spacing: skin.size.s8) {
                AinkradTextField(text: $comment, placeholder: "Comment — @mention an agent to wake it").onSubmit {
                    send(item)
                }
                AinkradButton(title: "Send", style: .secondary) { send(item) }.compact().fixedSize().disabled(
                    comment.trimmingCharacters(in: .whitespaces).isEmpty)
            }
        }
    }

    /// "agent:3" as the agent's name.
    private func who(_ actor: String) -> String {
        guard actor.hasPrefix("agent:"), let id = Int64(actor.dropFirst("agent:".count)),
            let agent = facts.model.agents[id]
        else { return actor }
        return agent.name
    }

    private func send(_ item: WorkItem) {
        store.comment(on: item, comment)
        comment = ""
    }
}
