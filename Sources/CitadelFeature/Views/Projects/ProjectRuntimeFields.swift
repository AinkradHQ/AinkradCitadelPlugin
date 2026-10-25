import AinkradAppKit
import SwiftUI

/// Runtime from API minor 18: the tags a runner needs, how many runs go at once, the run timeout and how long
/// worktrees are kept (stored and shown; dispatch does not enforce them yet), and the hosts agents reach without
/// asking.
struct ProjectsRunnersSection: View {
    let store: CitadelStore
    let facts: ProjectFacts
    @Environment(\.ainkradSkin) private var skin

    private var project: ProjectInfo { facts.project }

    /// Every tag a runner carries, plus the project's own, in name order.
    private var tags: [String] {
        Set(facts.model.runnersPage.runners.flatMap(\.tags) + project.runnerTags).sorted()
    }

    var body: some View {
        ConfigSection(title: "Runners", subtitle: "where this project's runs execute") {
            Text(skin.labelCased("Required runner tags")).citadelFont("t10", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.muted))
            if tags.isEmpty {
                Text("No runner has registered a tag yet.").citadelFont("t11").foregroundStyle(
                    skin.color(skin.text.faint))
            }
            AinkradCardGrid(columns: 4, spacing: skin.size.s8) {
                ForEach(tags, id: \.self) { tag in
                    let on = project.runnerTags.contains(tag)
                    let having = facts.model.runnersPage.runners.filter { $0.tags.contains(tag) }
                    AinkradChoiceCard(
                        isOn: on, minHeight: skin.size.s46,
                        action: {
                            store.setRuntime(
                                project, tags: on ? project.runnerTags.filter { $0 != tag } : project.runnerTags + [tag]
                            )
                        }
                    ) {
                        AinkradCheckBox(isOn: on)
                        VStack(alignment: .leading, spacing: skin.size.s1) {
                            Text(tag).citadelFont("t12", weight: "semibold", mono: true).foregroundStyle(
                                skin.color(skin.text.primary))
                            Text("\(having.count) runners · \(having.filter { $0.status == "online" }.count) online")
                                .citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
            }
            stepper("Parallel runs", value: project.maxParallelRuns ?? 4, in: 1...12, step: 1, unit: "") {
                store.setRuntime(project, parallel: $0)
            }
            stepper(
                "Run timeout", value: (project.runTimeoutSecs ?? 3_600) / 60, in: 10...240, step: 10, unit: " min"
            ) { store.setRuntime(project, timeoutSecs: $0 * 60) }
            stepper("Keep worktrees", value: project.worktreeKeepDays ?? 7, in: 0...30, step: 1, unit: " days") {
                store.setRuntime(project, keepDays: $0)
            }
        }
    }

    private func stepper(
        _ label: String, value: Int, in range: ClosedRange<Int>, step: Int, unit: String,
        set: @escaping (Int) -> Void
    ) -> some View {
        HStack(spacing: skin.size.s12) {
            Text(label).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted)).frame(
                width: skin.size.s120, alignment: .leading)
            AinkradStepper(
                value: Binding(get: { min(max(value, range.lowerBound), range.upperBound) }, set: set), in: range,
                step: step
            )
            .fixedSize()
            if !unit.isEmpty {
                Text(unit.trimmingCharacters(in: .whitespaces)).citadelFont("t12").foregroundStyle(
                    skin.color(skin.text.muted))
            }
            Spacer(minLength: 0)
        }
    }
}

struct ProjectsNetworkSection: View {
    let store: CitadelStore
    let facts: ProjectFacts
    @State private var adding = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let hosts = facts.profile?.networkHosts ?? []
        let id = facts.project.id
        ConfigSection(
            title: "Network", subtitle: "\(hosts.count) hosts allowed without asking · everything else is an approval"
        ) {
            AinkradButton(title: "＋ Add host", style: .ghost) { adding = true }.borderless().compact().fixedSize()
        } content: {
            AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                if hosts.isEmpty {
                    Text("No host is allowed without asking.").citadelFont("t11").foregroundStyle(
                        skin.color(skin.text.faint))
                }
                ForEach(hosts, id: \.self) { host in
                    AinkradChip(label: host) { store.setNetworkHosts(project: id, hosts.filter { $0 != host }) }
                }
            }
        }
        .ainkradSheet(isPresented: $adding) {
            PromptSheet(
                title: "Allow a host without asking", message: "A host name, such as crates.io or *.github.com.",
                placeholder: "registry.npmjs.org", confirmTitle: "Allow", text: "", isPresented: $adding
            ) { entry in
                let host = entry.trimmingCharacters(in: .whitespaces).lowercased()
                guard !host.isEmpty, !hosts.contains(host) else { return }
                store.setNetworkHosts(project: id, hosts + [host])
            }
        }
    }
}
