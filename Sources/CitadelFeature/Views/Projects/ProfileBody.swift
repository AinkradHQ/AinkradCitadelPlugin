import AinkradAppKit
import CitadelClient
import SwiftUI

/// The profile's groups, top to bottom: proposals, repositories, then the two-column groups and the limits.
struct ProfileBody: View {
    let store: CitadelStore
    let model: CompanyModel
    let project: ProjectInfo
    @State private var showsHistory = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var profile: ProfileInfo { model.projectsPage.profiles[project.id] ?? ProfileInfo() }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            proposals.id(ProfileSection.proposals)
            RepositoriesGroup(store: store, model: model, project: project).id(ProfileSection.repositories)
            pair(
                DoneGroup(store: store, project: project.id, profile: profile).id(ProfileSection.done),
                BranchesGroup(store: store, project: project.id, profile: profile).id(ProfileSection.branches))
            pair(
                EnvironmentsGroup(profile: profile).id(ProfileSection.environments),
                ModelsGroup(model: model, project: project.id, profile: profile).id(ProfileSection.models))
            pair(
                PoliciesGroup(store: store, project: project.id, profile: profile).id(ProfileSection.policies),
                DocsGroup(profile: profile).id(ProfileSection.docs))
            ProjectLimitsGroup(store: store, model: model, project: project).id(ProfileSection.limits)
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: profile.proposals.map(\.id))
    }

    /// Two groups side by side, equal widths and heights (a `Grid` would size its columns to the groups' ideal,
    /// untruncated widths).
    private func pair(_ left: some View, _ right: some View) -> some View {
        HStack(alignment: .top, spacing: skin.size.s12) {
            left.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            right.frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        }
        .fixedSize(horizontal: false, vertical: true)
    }

    /// "PROPOSED BY AGENTS · 2 waiting · History →" and a card per proposal: the diff, the reason, Reject… / Accept.
    /// With none waiting the header stays, so History is always one click away.
    private var proposals: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(spacing: skin.size.s8) {
                Text(skin.labelCased("Proposed by agents")).citadelFont("t10", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.muted))
                AinkradBadge(
                    text: profile.proposals.isEmpty ? "none waiting" : "\(profile.proposals.count) waiting",
                    tint: skin.color(profile.proposals.isEmpty ? skin.text.muted : skin.palette.accentViolet))
                Spacer(minLength: skin.size.s8)
                AinkradButton(title: "History →", style: .ghost) {
                    store.loadProfileHistory(project.id)
                    showsHistory = true
                }
                .borderless().secondaryAccent().compact().fixedSize()
            }
            ForEach(profile.proposals) { proposal in
                ProposalRow(store: store, model: model, project: project.id, profile: profile, proposal: proposal)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .ainkradSheet(isPresented: $showsHistory) {
            ProfileHistorySheet(model: model, project: project, isPresented: $showsHistory)
        }
    }
}

/// One agent proposal (decision #48: a person accepts it; it never applies itself).
private struct ProposalRow: View {
    let store: CitadelStore
    let model: CompanyModel
    let project: Int64
    let profile: ProfileInfo
    let proposal: ProposalInfo
    @State private var rejecting = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let agent = model.agent(proposal.agentID)
        let diff = profile.diff(proposal)
        AinkradProposalCard(
            author: agent.map(\.nameAndRole) ?? "An agent", title: proposal.title,
            tag: proposal.field.replacingOccurrences(of: "_", with: " "), oldValue: diff.old, newValue: diff.new,
            reason: proposal.rationale,
            onAccept: { store.decide(proposal, project: project, accept: true) },
            onReject: { rejecting = true }
        ) {
            if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s24) }
        }
        .ainkradSheet(isPresented: $rejecting) {
            PromptSheet(
                title: "Reject \(proposal.title)?",
                message: "The profile stays as it is. A reason is optional; the agent sees it.",
                placeholder: "Why not (optional)", confirmTitle: "Reject", isDestructive: true, allowsEmpty: true,
                text: "", isPresented: $rejecting
            ) { store.decide(proposal, project: project, accept: false, reason: $0) }
        }
    }
}

/// A profile group: a card with its title (and an optional note and action) over its rows.
struct ProfileGroup<Trailing: View, Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder var trailing: Trailing
    @ViewBuilder var content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s4) {
                HStack(spacing: skin.size.s8) {
                    Text(title).citadelFont("t13", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                    if let note {
                        Text(note).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    }
                    Spacer(minLength: skin.size.s8)
                    trailing
                }
                .padding(.bottom, skin.size.s4)
                content
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        }
    }
}

extension ProfileGroup where Trailing == EmptyView {
    init(title: String, note: String? = nil, @ViewBuilder content: () -> Content) {
        self.init(title: title, note: note, trailing: { EmptyView() }, content: content)
    }
}

/// A label and its value on one line (the mockup's `.srow`), the row lifting its fill on hover.
struct ProfileRow<Value: View, Trailing: View>: View {
    let label: String
    @ViewBuilder var value: Value
    @ViewBuilder var trailing: Trailing
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s10) {
            Text(label).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                .frame(width: skin.size.s96, alignment: .leading)
            value.citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                .truncationMode(.tail)
            Spacer(minLength: skin.size.s4)
            trailing
        }
        .padding(.vertical, skin.size.s4)
        .padding(.horizontal, skin.size.s4)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s6, style: .continuous)
                .fill(skin.color(skin.palette.white).opacity(hovering ? skin.opacity.o05 : 0))
        )
        .padding(.horizontal, -skin.size.s4)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

extension ProfileRow where Trailing == EmptyView {
    init(label: String, @ViewBuilder value: () -> Value) {
        self.init(label: label, value: value, trailing: { EmptyView() })
    }
}

// MARK: - Definition of done, branches

private struct DoneGroup: View {
    let store: CitadelStore
    let project: Int64
    let profile: ProfileInfo
    @State private var draft = ""
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        ProfileGroup(title: "Definition of done") {
            ForEach(profile.definitionOfDone, id: \.self) { rule in
                HStack(spacing: skin.size.s8) {
                    AinkradCheckbox(isOn: .constant(true))
                    Text(rule).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.vertical, skin.size.s2)
            }
            HStack(spacing: skin.size.s8) {
                Text("＋").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                AinkradTextField(text: $draft, placeholder: "Add a rule…").compact()
                    .onSubmit(add)
            }
            .padding(.top, skin.size.s2)
        }
    }

    private func add() {
        let rule = draft.trimmingCharacters(in: .whitespaces)
        guard !rule.isEmpty else { return }
        draft = ""
        store.updateProfile(project: project, Schemas.ProfilePatch(definitionOfDone: profile.definitionOfDone + [rule]))
    }
}

private struct BranchesGroup: View {
    let store: CitadelStore
    let project: Int64
    let profile: ProfileInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        ProfileGroup(title: "Branches & PRs") {
            ProfileRow(label: "PR base") { Text("each repo's default branch") }
            ProfileRow(label: "Protected") {
                Text(profile.protectedBranches.joined(separator: " · ")).citadelFont("t12", mono: true)
            }
            ProfileRow(label: "Branch name") {
                Text("\(profile.branchPattern) · same in every repo").citadelFont("t12", mono: true)
            }
            ProfileRow(label: "Merge") {
                AinkradSegmentedPicker(
                    items: ["merge", "squash", "rebase"],
                    selection: Binding(
                        get: { profile.mergeMethod },
                        set: {
                            store.updateProfile(
                                project: project, .init(mergeMethod: .init(value1: .init(rawValue: $0))))
                        }),
                    label: { $0.capitalized }
                )
                .fixedSize()
            }
            ProfileRow(label: "Who merges") {
                AinkradSegmentedPicker(
                    items: ["owner", "product_owner", "lead"],
                    selection: Binding(
                        get: { profile.mergedBy },
                        set: {
                            store.updateProfile(project: project, .init(mergedBy: .init(value1: .init(rawValue: $0))))
                        }),
                    label: { ["owner": "You", "product_owner": "PO", "lead": "Lead"][$0] ?? $0 }
                )
                .fixedSize()
            }
        }
    }
}
