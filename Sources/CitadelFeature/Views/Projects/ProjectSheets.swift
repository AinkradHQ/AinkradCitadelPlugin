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
    @State private var failure: ActionFailure?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("New project").citadelFont("t15", weight: "semibold")
            AinkradFormRow(title: "Name") { AinkradTextField(text: $name, placeholder: "Citadel Core") }
            AinkradFormRow(title: "Key", help: "CIT → CIT-12") {
                AinkradTextField(text: $key, placeholder: "CIT").monospaced()
            }
            AinkradFormRow(title: "Mode") {
                AinkradSegmentedPicker(items: ["scrum", "kanban"], selection: $mode) { $0.capitalized }.fixedSize()
            }
            if let failure { RefusalLine(failure: failure) }
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { isPresented = false }.fixedSize()
                AinkradButton(title: "Create") {
                    failure = nil
                    store.createProject(name: name, key: key, mode: mode) { refused in
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
        let who = agent.map { "\($0.name) (\($0.role))" } ?? (change.byPerson ? "You" : "Citadel")
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
