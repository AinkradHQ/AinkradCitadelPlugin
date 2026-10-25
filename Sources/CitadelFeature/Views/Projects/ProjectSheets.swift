import AinkradAppKit
import SwiftUI

/// "＋ New project": its name, its issue key (`CIT` for `CIT-12`) and its mode. A taken or malformed key is the
/// server's 409, shown here with Copy error.
struct NewProjectSheet: View {
    let store: CitadelStore
    @Binding var isPresented: Bool
    @State private var name = ""
    @State private var key = ""
    @State private var mode = "scrum"
    @State private var team: Int64?
    /// The teams picked, in the order picked; the first owns the project (API minor 18).
    @State private var teams: [Int64] = []
    @State private var iconIndex: Int
    @State private var colorIndex: Int
    @State private var failure: ActionFailure?
    @Environment(\.ainkradSkin) private var skin

    private var availableTeams: [(team: TeamInfo, department: String)] {
        (store.model?.departments ?? []).flatMap { department in department.teams.map { ($0, department.name) } }
    }

    init(store: CitadelStore, isPresented: Binding<Bool>) {
        self.store = store
        _isPresented = isPresented
        // The icon and colour the project would take by its place in the list, until one is picked.
        let count = store.model?.projects.count ?? 0
        _iconIndex = State(initialValue: count % ProjectLook.glyphs.count)
        _colorIndex = State(initialValue: count % ProjectIdentity.pairs.count)
    }

    /// The colours the new project takes: the pair picked (API minor 18), else the next in the list.
    private var previewTint: (Color, Color) {
        if store.hasTrancheB { return ProjectIdentity.pair(at: colorIndex) }
        let pair = ProjectLook.pairs[(store.model?.projects.count ?? 0) % ProjectLook.pairs.count]
        return (pair.lightColor, pair.deepColor)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s14) {
            HStack(spacing: skin.size.s12) {
                ProjectMark(
                    glyph: store.hasTrancheB ? ProjectLook.glyphs[iconIndex] : ProjectLook.glyphs[0],
                    tint: previewTint, side: skin.size.s44)
                Text("New project").citadelFont("t15", weight: "semibold")
            }
            AinkradFormRow(title: "Name") { AinkradTextField(text: $name, placeholder: "Citadel Core") }
            AinkradFormRow(title: "Key", help: "\(key.isEmpty ? "CIT" : key.uppercased())-1, -2 …") {
                AinkradTextField(text: $key, placeholder: "CIT").monospaced()
            }
            if store.hasTrancheB {
                AinkradFormRow(title: "Icon") {
                    AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                        ForEach(Array(ProjectLook.glyphs.enumerated()), id: \.offset) { index, glyph in
                            ProjectsIconTile(glyph: glyph, isOn: iconIndex == index) { iconIndex = index }
                        }
                    }
                }
                AinkradFormRow(title: "Colour") {
                    AinkradFlowLayout(spacing: skin.size.s8, lineSpacing: skin.size.s8) {
                        ForEach(0..<ProjectIdentity.pairs.count, id: \.self) { index in
                            ProjectsColourSwatch(tint: ProjectIdentity.pair(at: index), isOn: colorIndex == index) {
                                colorIndex = index
                            }
                        }
                    }
                }
            }
            AinkradFormRow(title: "Cadence") {
                AinkradCardGrid(columns: 2) {
                    AinkradChoiceCard(
                        isOn: mode == "scrum", minHeight: skin.size.s64, axis: .vertical, action: { mode = "scrum" }
                    ) {
                        AinkradChoiceText(title: "Sprints", caption: "Plan, commit, burn down")
                    }
                    AinkradChoiceCard(
                        isOn: mode == "kanban", minHeight: skin.size.s64, axis: .vertical, action: { mode = "kanban" }
                    ) {
                        AinkradChoiceText(title: "Kanban", caption: "A continuous flow, no sprints")
                    }
                }
            }
            if !availableTeams.isEmpty {
                AinkradFormRow(
                    title: store.hasTrancheB ? "Teams" : "Team",
                    help: store.hasTrancheB ? "Pick one or more — the first you pick owns the project." : nil
                ) {
                    AinkradCardGrid(columns: 2) {
                        ForEach(availableTeams, id: \.team.id) { entry in
                            let picked = store.hasTrancheB ? teams.contains(entry.team.id) : team == entry.team.id
                            AinkradChoiceCard(
                                isOn: picked, minHeight: skin.size.s46, action: { pick(entry.team.id) }
                            ) {
                                AinkradChoiceText(
                                    title: entry.team.name
                                        + (store.hasTrancheB && teams.first == entry.team.id ? " · owner" : ""),
                                    caption: "\(entry.department) · \(entry.team.seats.count) agents")
                            }
                        }
                    }
                }
            }
            if let failure { RefusalLine(failure: failure) }
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { isPresented = false }.fixedSize()
                AinkradButton(title: "Create project") {
                    failure = nil
                    store.createProject(
                        name: name, key: key, mode: mode, team: team, icon: ProjectLook.glyphs[iconIndex],
                        color: ProjectIdentity.pairs[colorIndex].light, teams: teams
                    ) { refused in
                        if let refused { failure = refused } else { isPresented = false }
                    }
                }
                .fixedSize()
                .disabled(name.trimmingCharacters(in: .whitespaces).isEmpty || !Self.isKey(key))
            }
        }
        .padding(skin.size.s20)
        .frame(width: skin.size.s480)
    }

    private func pick(_ id: Int64) {
        guard store.hasTrancheB else {
            team = id
            return
        }
        if let index = teams.firstIndex(of: id) { teams.remove(at: index) } else { teams.append(id) }
    }

    /// The server's rule, checked before it is asked: `CIT`, `AMC2`.
    static func isKey(_ text: String) -> Bool {
        text.uppercased().wholeMatch(of: /[A-Z][A-Z0-9]{0,9}/) != nil
    }
}

/// "History →": every change to the profile and every agent proposal, newest first, with who and why.
struct ProfileHistorySheet: View {
    let model: CompanyModel
    let project: ProjectInfo
    @Binding var isPresented: Bool
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let history = model.projectsPage.history[project.id]
        VStack(alignment: .leading, spacing: skin.size.s12) {
            HStack {
                Text("\(project.name) · profile history").citadelFont("t15", weight: "semibold")
                Spacer()
                AinkradButton(title: "Done", style: .ghost) { isPresented = false }.fixedSize()
            }
            if let history, history.isEmpty {
                Text("No changes yet.").citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            } else if let history {
                ScrollView {
                    VStack(alignment: .leading, spacing: skin.size.s8) {
                        ForEach(history) { row($0) }
                    }
                }
                .frame(maxHeight: skin.size.s440)
            } else {
                FirstLoadView()
            }
        }
        .padding(skin.size.s20)
        .frame(width: skin.size.s520)
    }

    private func row(_ change: ProfileChangeInfo) -> some View {
        let agent = model.agent(change.agentID)
        let who = agent.map(\.nameAndRole) ?? (change.byPerson ? "You" : "Citadel")
        return HStack(alignment: .top, spacing: skin.size.s10) {
            Group {
                if let agent {
                    AgentFigure(agent: agent, model: model, size: skin.size.s18)
                } else {
                    Image(systemName: change.byPerson ? "person" : "gearshape").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.muted))
                }
            }
            .frame(width: skin.size.s18)
            VStack(alignment: .leading, spacing: skin.size.s2) {
                (Text(who).foregroundStyle(skin.color(skin.text.primary))
                    + Text(" \(change.line)").foregroundStyle(skin.color(skin.text.muted)))
                    .citadelFont("t12")
                if let why = change.why {
                    Text(why).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            Spacer(minLength: skin.size.s8)
            Text(RequirementThreadView.time(change.at)).citadelFont("t11", mono: true)
                .foregroundStyle(skin.color(skin.text.faint))
        }
    }
}

/// An icon in the New project sheet's grid (`.pn-icons span`): a glyph on a soft tile, blue rim when picked.
private struct ProjectsIconTile: View {
    let glyph: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        AinkradTapArea(action: action) {
            Text(glyph).citadelFont("t15").foregroundStyle(skin.color(skin.text.primary))
                .frame(width: skin.size.s36, height: skin.size.s36)
                .background(
                    shape.fill(
                        isOn
                            ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o25)
                            : skin.color(.palette("foreground", hovering ? skin.opacity.o08 : skin.opacity.o05)))
                )
                .overlay(
                    shape.strokeBorder(
                        isOn
                            ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o60)
                            : skin.color(.palette("foreground", skin.opacity.o08))))
        }
        .onHover { hovering = $0 }
    }
}

/// A colour pair in the sheet (`.pn-cols span`): its gradient, ringed when picked.
private struct ProjectsColourSwatch: View {
    let tint: (Color, Color)
    let isOn: Bool
    let action: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(action: action) {
            Circle().fill(LinearGradient(colors: [tint.0, tint.1], startPoint: .topLeading, endPoint: .bottomTrailing))
                .frame(width: skin.size.s28, height: skin.size.s28)
                .padding(skin.size.s3)
                .overlay(
                    Circle().strokeBorder(
                        skin.color(.palette("foreground", isOn ? 1 : 0)), lineWidth: skin.size.s2))
        }
    }
}
