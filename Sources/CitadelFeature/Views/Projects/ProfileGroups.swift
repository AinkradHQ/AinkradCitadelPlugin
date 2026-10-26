import AinkradAppKit
import CitadelClient
import SwiftUI

/// Who may deploy where (configuration only — there is no deploy action).
struct EnvironmentsGroup: View {
    let profile: ProfileInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        ProfileGroup(title: "Environments") {
            ForEach(profile.environments, id: \.name) { environment in
                ProfileRow(label: environment.name) {
                    Text(environment.url.isEmpty ? "runner worktrees" : environment.url).citadelFont("t12", mono: true)
                } trailing: {
                    switch environment.deploy {
                    case "agents": AinkradBadge(text: "agents", status: .success)
                    case "owner": AinkradBadge(text: "you only", status: .danger)
                    default: AinkradBadge(text: "ask first", status: .warning)
                    }
                }
            }
            ProfileRow(label: "Secrets") { Text("server vault · never in the profile") }
        }
    }
}

/// The model each role runs on here when it has none of its own, and the small-task rule.
struct ModelsGroup: View {
    let model: CompanyModel
    let project: Int64
    let profile: ProfileInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        ProfileGroup(title: "Models per role") {
            ForEach(profile.models, id: \.role) { role in
                ProfileRow(label: role.role) {
                    HStack(spacing: skin.size.s6) {
                        let harness = Self.harness(of: role.model)
                        AinkradBadge(
                            text: AgentLook.harnessName(harness),
                            tint: AgentLook.harness(harness)?.color ?? theme.foreground)
                        Text(role.small.map { "\(role.model) · small: \($0)" } ?? role.model)
                    }
                }
            }
            if let small = model.projectsPage.settings[project]?.first(where: { $0.key == "routing.small_max_points" })
            {
                ProfileRow(label: "Small task") { Text("≤ \(small.value) pts → small tier") }
            }
        }
    }

    /// The harness a model runs under, from its name.
    static func harness(of model: String) -> String {
        let name = model.lowercased()
        if name.contains("gpt") || name.contains("codex") { return "codex" }
        if name.contains("gemini") { return "agy" }
        if name.contains("qwen") || name.contains("glm") || name.contains("kimi") { return "opencode" }
        return "claude"
    }
}

/// Plan approval (decision #40), the permission mode and network access.
struct PoliciesGroup: View {
    let store: CitadelStore
    let project: Int64
    let profile: ProfileInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        ProfileGroup(title: "Policies") {
            ProfileRow(label: "Plan approval") {
                AinkradSegmentedPicker(
                    items: ["owner", "product_owner"],
                    selection: Binding(
                        get: { profile.sprintApproval },
                        set: {
                            store.updateProfile(
                                project: project, .init(sprintApproval: .init(value1: .init(rawValue: $0))))
                        }),
                    label: { $0 == "owner" ? "Owner (you)" : "Product owner" }
                )
                .fixedSize()
            }
            ProfileRow(label: "Permissions") {
                AinkradSegmentedPicker(
                    items: ["ask", "accept_edits", "sandboxed"],
                    selection: Binding(
                        get: { profile.permissionMode },
                        set: {
                            store.updateProfile(
                                project: project, .init(permissionMode: .init(value1: .init(rawValue: $0))))
                        }),
                    label: { ["ask": "Ask", "accept_edits": "Write", "sandboxed": "Full"][$0] ?? $0 }
                )
            }
            if let policy = store.model?.projectsPage.policies[project] {
                AllowlistRow(store: store, project: project, policy: policy)
            }
            ProfileRow(label: "Network") {
                Text(["on": "on · every run", "ask": "off · ask per run"][profile.network] ?? "off")
            } trailing: {
                AinkradToggle(
                    isOn: Binding(
                        get: { profile.network == "on" },
                        set: {
                            store.updateProfile(
                                project: project, .init(network: .init(value1: .init(rawValue: $0 ? "on" : "ask"))))
                        }))
            }
        }
    }
}

/// The permission policy's allowlist (API minor 11): what goes ahead without asking — a tool (`Edit`) or
/// `<tool>:<command prefix>` (`Bash:npm run`). × removes one, the field adds one on Return; the policy is replaced whole.
struct AllowlistRow: View {
    let store: CitadelStore
    let project: Int64
    let policy: PolicyInfo
    @State private var draft = ""
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        ProfileRow(label: "Allowed") {
            HStack(spacing: skin.size.s6) {
                if policy.allow.isEmpty { Text("nothing without asking") }
                ForEach(policy.allow, id: \.self) { entry in
                    AinkradChip(label: entry) {
                        store.setAllowlist(project: project, policy.allow.filter { $0 != entry })
                    }
                }
            }
        } trailing: {
            AinkradTextField(text: $draft, placeholder: "Add — Bash:cargo test").compact().monospaced()
                .onSubmit(add).frame(width: skin.size.s160)
        }
    }

    private func add() {
        let entry = draft.trimmingCharacters(in: .whitespaces)
        draft = ""
        guard !entry.isEmpty, !policy.allow.contains(entry) else { return }
        store.setAllowlist(project: project, policy.allow + [entry])
    }
}

/// Conventions and linked docs: a card per doc, and a "＋ Link a doc" card that takes a path or URL.
struct DocsGroup: View {
    let store: CitadelStore
    let project: Int64
    let profile: ProfileInfo
    @State private var draft = ""
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        ProfileGroup(title: "Docs & links") {
            ProfileRow(label: "Commits") { Text(profile.conventions.isEmpty ? "—" : profile.conventions) }
            if !profile.stack.isEmpty { ProfileRow(label: "Stack") { Text(profile.stack) } }
            AinkradCardGrid(columns: 2) {
                ForEach(profile.docs, id: \.self) { doc in
                    AinkradChoiceCard(minHeight: skin.size.s46) {
                        Text(doc).citadelFont("t12", mono: true).foregroundStyle(theme.accentSecondary).lineLimit(1)
                            .truncationMode(.middle)
                        Spacer(minLength: skin.size.s4)
                        AinkradIconButton(systemName: "xmark", size: skin.size.s18, tooltip: "Unlink") {
                            store.updateProfile(project: project, .init(docs: profile.docs.filter { $0 != doc }))
                        }
                        .bare()
                    }
                }
                AinkradChoiceCard(isAdd: true, minHeight: skin.size.s46) {
                    AinkradTextField(text: $draft, placeholder: "＋ Link a doc — path or URL").compact().onSubmit(link)
                }
            }
        }
    }

    private func link() {
        let doc = draft.trimmingCharacters(in: .whitespaces)
        draft = ""
        guard !doc.isEmpty, !profile.docs.contains(doc) else { return }
        store.updateProfile(project: project, .init(docs: profile.docs + [doc]))
    }
}

/// The project's limits (decision #52): each with its bounds, its value, and where it comes from — ↺ resets an
/// override to the company's value. The rest of the company's limits are on screen 16.
struct ProjectLimitsGroup: View {
    let store: CitadelStore
    let model: CompanyModel
    let project: ProjectInfo
    @State private var showsAll = false
    @Environment(\.ainkradSkin) private var skin

    /// The limits shown first; any overridden here is shown too.
    static let main = [
        "run.stall_after_secs", "run.token_cap", "run.stuck_after_secs", "profile.budget_bytes",
        "knowledge.budget_bytes", "skills.budget_bytes", "repair.budget", "issue.idle_escalate_secs",
    ]

    var body: some View {
        let scope = "project:\(project.id)"
        let page = model.projectsPage
        let all = page.limits(project.id)
        let shown =
            showsAll
            ? all
            : all.filter { Self.main.contains($0.key) || $0.isSet(at: scope) }
                .sorted { (Self.main.firstIndex(of: $0.key) ?? 99) < (Self.main.firstIndex(of: $1.key) ?? 99) }
        ProfileGroup(title: "Limits", note: "this project · most specific wins: server → company → project") {
            AinkradButton(title: "All limits (company) →", style: .ghost) {
                model.limitsPage.section = .limits
                store.isShowingSettings = true
            }
            .borderless().secondaryAccent().compact().fixedSize()
        } content: {
            ForEach(shown) { setting in
                AinkradScopedValue(
                    label: LimitNames.name(setting.key), bounds: setting.bounds,
                    value: Binding(get: { setting.text }, set: { store.setLimit(setting, scope: scope, text: $0) }),
                    scope: setting.chip(at: scope, inherited: page.inherited(setting.key)),
                    validate: setting.accepts,
                    onReset: setting.isSet(at: scope) ? { store.resetLimit(setting, scope: scope) } : nil
                )
                .padding(.vertical, skin.size.s2)
            }
            if all.count > shown.count || showsAll {
                AinkradButton(title: showsAll ? "Fewer" : "+ \(all.count - shown.count) more", style: .ghost) {
                    showsAll.toggle()
                }
                .borderless().compact().fixedSize()
            }
        }
    }
}
