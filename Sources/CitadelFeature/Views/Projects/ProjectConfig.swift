import AinkradAppKit
import CitadelClient
import SwiftUI

/// A configuration section (`.pc-sec`): title and faint subtitle over its content.
struct ConfigSection<Trailing: View, Content: View>: View {
    let title: String
    var subtitle: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(spacing: skin.size.s8) {
                Text(title).citadelFont("t14", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                if let subtitle {
                    Text(subtitle).citadelFont("t11_5").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
                Spacer(minLength: skin.size.s8)
                trailing
            }
            content
        }
        .padding(skin.size.s16)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o03))))
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o07))))
    }
}

extension ConfigSection where Trailing == EmptyView {
    init(title: String, subtitle: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, subtitle: subtitle, trailing: { EmptyView() }, content: content)
    }
}

/// Teams: the server keeps one owning team per project (MISSING `team_ids`), so picking a team makes it the owner.
struct ConfigTeams: View {
    let store: CitadelStore
    let facts: ProjectFacts
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        ConfigSection(title: "Teams on this project", subtitle: "the owner plans sprints with the PO") {
            AinkradCardGrid(columns: 2, spacing: skin.size.s16) {
                ForEach(facts.model.departments) { department in
                    ForEach(department.teams) { team in
                        let isOwner = team.id == facts.project.teamID
                        AinkradChoiceCard(
                            isOn: isOwner, minHeight: skin.size.s80,
                            action: { store.setTeam(team, project: facts.project) }
                        ) {
                            AinkradCheckBox(isOn: isOwner)
                            VStack(alignment: .leading, spacing: skin.size.s3) {
                                HStack(spacing: skin.size.s6) {
                                    Text(team.name).citadelFont("t12_5", weight: "semibold").foregroundStyle(
                                        skin.color(skin.text.primary))
                                    if isOwner { AinkradBadge(text: "owner", status: .warning) }
                                }
                                Text("\(department.name) · \(team.seats.count) agents")
                                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                }
            }
        }
    }
}

struct ConfigRepos: View {
    let store: CitadelStore
    let facts: ProjectFacts

    var body: some View { RepositoriesGroup(store: store, model: facts.model, project: facts.project) }
}

/// Rules: the definition of done, branches and merging, and the policies, each as the prototype's choice cards.
struct ConfigRules: View {
    let store: CitadelStore
    let facts: ProjectFacts
    @State private var draft = ""
    @Environment(\.ainkradSkin) private var skin

    private var profile: ProfileInfo { facts.profile ?? ProfileInfo() }
    private var id: Int64 { facts.project.id }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s16) {
            ConfigSection(
                title: "Definition of done",
                subtitle: "\(profile.definitionOfDone.count) rules · QA checks every issue against them"
            ) {
                AinkradCardGrid(columns: 2) {
                    ForEach(profile.definitionOfDone, id: \.self) { rule in
                        AinkradToggleCard(title: rule, isOn: true) {
                            store.updateProfile(
                                project: id,
                                Schemas.ProfilePatch(definitionOfDone: profile.definitionOfDone.filter { $0 != rule }))
                        }
                    }
                    AinkradChoiceCard(isAdd: true, minHeight: skin.size.s46) {
                        AinkradTextField(text: $draft, placeholder: "Add a rule — e.g. Docs updated").compact()
                            .onSubmit(add)
                        AinkradButton(title: "Add", style: .secondary) { add() }.compact().fixedSize()
                    }
                }
            }
            ConfigSection(title: "Branches & merging", subtitle: "the same rules in every repo") {
                AinkradCardGrid(columns: 3) {
                    kv("PR base", "each repo's default branch")
                    kv("Branch name", profile.branchPattern, mono: true)
                    kv("Protected", profile.protectedBranches.joined(separator: " · "), mono: true)
                }
                choices(
                    [
                        ("merge", "Merge commit", "Keeps every commit"), ("squash", "Squash", "One commit per PR"),
                        ("rebase", "Rebase", "Linear history"),
                    ],
                    selected: profile.mergeMethod
                ) { store.updateProfile(project: id, .init(mergeMethod: .init(value1: .init(rawValue: $0)))) }
                Text("Who merges").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                choices(
                    [
                        ("owner", "You", "Every PR waits for you"), ("product_owner", "Product owner", "The PO merges"),
                        ("lead", "Team lead", "The lead merges"),
                    ],
                    selected: profile.mergedBy
                ) { store.updateProfile(project: id, .init(mergedBy: .init(value1: .init(rawValue: $0)))) }
            }
            ConfigSection(title: "Policies") {
                choices(
                    [
                        ("owner", "Owner (you)", "You approve each sprint plan"),
                        ("product_owner", "Product owner", "The PO approves plans"),
                    ],
                    selected: profile.sprintApproval
                ) { store.updateProfile(project: id, .init(sprintApproval: .init(value1: .init(rawValue: $0)))) }
                Text("Default permissions").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                choices(
                    [
                        ("ask", "Read", "Ask before anything"), ("accept_edits", "Write", "Edits go ahead"),
                        ("sandboxed", "Full", "Sandboxed, no asking"),
                    ],
                    selected: profile.permissionMode
                ) { store.updateProfile(project: id, .init(permissionMode: .init(value1: .init(rawValue: $0)))) }
                AinkradToggleCard(title: "Network access without asking", isOn: profile.network == "on") {
                    store.updateProfile(
                        project: id,
                        .init(network: .init(value1: .init(rawValue: profile.network == "on" ? "ask" : "on"))))
                }
            }
        }
    }

    private func add() {
        let rule = draft.trimmingCharacters(in: .whitespaces)
        guard !rule.isEmpty else { return }
        draft = ""
        store.updateProfile(project: id, Schemas.ProfilePatch(definitionOfDone: profile.definitionOfDone + [rule]))
        store.toast(AinkradRichToast(title: "Rule added", body: "QA checks it from the next issue.", status: .success))
    }

    private func kv(_ label: String, _ value: String, mono: Bool = false) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s2) {
            Text(label).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
            Text(value.isEmpty ? "—" : value).citadelFont("t11_5", mono: mono).foregroundStyle(
                skin.color(skin.text.primary)
            ).lineLimit(1)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, skin.size.s12).padding(.vertical, skin.size.s10)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)),
            in: RoundedRectangle(cornerRadius: skin.size.s11, style: .continuous))
    }

    private func choices(_ options: [(String, String, String)], selected: String, pick: @escaping (String) -> Void)
        -> some View
    {
        AinkradCardGrid(columns: options.count) {
            ForEach(options, id: \.0) { option in
                AinkradChoiceCard(
                    isOn: selected == option.0, minHeight: skin.size.s64, axis: .vertical, action: { pick(option.0) }
                ) {
                    AinkradChoiceText(title: option.1, caption: option.2)
                }
            }
        }
    }
}

/// Runtime: environments (read-only until the server carries deploy fields), the tool allowlist and the small-task
/// rule. Runners and the network host list wait on S10.
struct ConfigRuntime: View {
    let store: CitadelStore
    let facts: ProjectFacts
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let id = facts.project.id
        VStack(alignment: .leading, spacing: skin.size.s16) {
            if let profile = facts.profile {
                EnvironmentsGroup(profile: profile)
            }
            if let policy = facts.page.policies[id] {
                ConfigSection(title: "Tools allowed without asking", subtitle: "a tool, or tool:command prefix") {
                    AllowlistRow(store: store, project: id, policy: policy)
                }
            }
            if let small = facts.page.settings[id]?.first(where: { $0.key == "routing.small_max_points" }) {
                ConfigSection(title: "Small tasks", subtitle: "issues up to this many points use the small tier") {
                    AinkradStepper(
                        value: Binding(
                            get: { Int(small.value) },
                            set: { store.setLimit(small, scope: "project:\(id)", text: String($0)) }),
                        in: Int(small.min)...Int(small.max)
                    )
                    .fixedSize()
                }
            }
        }
    }
}

struct ConfigLimits: View {
    let store: CitadelStore
    let facts: ProjectFacts

    var body: some View { ProjectLimitsGroup(store: store, model: facts.model, project: facts.project) }
}

struct ConfigDocs: View {
    let store: CitadelStore
    let facts: ProjectFacts
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s16) {
            if let profile = facts.profile { DocsGroup(profile: profile) }
            KnowledgeGroup(store: store, model: facts.model, project: facts.project.id)
        }
    }
}

/// Context: how much of the profile budget a run's injected context uses. The rendered text waits on S12.
struct ConfigContext: View {
    let facts: ProjectFacts
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let profile = facts.profile ?? ProfileInfo()
        ConfigSection(title: "What a run sees", subtitle: "injected before the issue, on every run in this project") {
            AinkradBudgetBar(
                label: "Profile budget", value: Double(profile.injectedBytes),
                limit: Double(max(profile.budgetBytes, 1)))
            Text(
                "\(profile.injectedBytes.formatted(.byteCount(style: .file))) of \(profile.budgetBytes.formatted(.byteCount(style: .file))) · generated from Repos · Rules · Runtime · Limits"
            )
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
        }
    }
}
