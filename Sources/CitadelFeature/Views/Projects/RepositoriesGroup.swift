import AinkradAppKit
import SwiftUI

/// A project's repos (decision #51): one card each, dragged into the order agents see and PRs merge in (#54),
/// ★ the primary, ✕ to remove (the server refuses while an open issue touches it); then how an issue declares the
/// repos it touches.
struct RepositoriesGroup: View {
    let store: CitadelStore
    let model: CompanyModel
    let project: ProjectInfo
    @State private var adding = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    private var page: ProjectsPage { model.projectsPage }
    private var repos: [RepoInfo] { page.repos[project.id] ?? [] }

    var body: some View {
        ProfileGroup(
            title: "Repositories", note: "\(repos.count) · drag to reorder · each gets its own worktree and PR"
        ) {
            AinkradButton(title: "＋ Add repository", style: .secondary) { adding = true }
                .secondaryAccent().compact().fixedSize()
        } content: {
            if let problem = page.problem {
                AinkradBanner(
                    message: problem.message, status: .warning, actionTitle: "Copy error", action: { problem.copy() },
                    onDismiss: { page.problem = nil })
            }
            AinkradReorderList(
                items: Binding(get: { repos }, set: { store.reorderRepos(project: project.id, $0) })
            ) { repo in
                RepoCard(
                    store: store, repo: repo, project: project.id,
                    stack: store.hasTrancheB ? repo.stack : (repo.isPrimary ? page.profiles[project.id]?.stack : nil))
            }
            declared.padding(.top, skin.size.s8)
        }
        .ainkradSheet(isPresented: $adding) {
            AddRepoSheet(
                isPresented: $adding, probes: store.hasTrancheB,
                probe: { name, url, forge, token, done in
                    store.probeRepo(
                        project: project.id, name: name, url: url, forge: forge, tokenFile: token, done: done)
                },
                add: { name, url, branch, forge, token, probe in
                    store.addRepo(
                        project: project.id, name: name, url: url, branch: branch, forge: forge, tokenFile: token,
                        probe: probe)
                })
        }
    }

    /// "ISSUES DECLARE THE REPOS THEY TOUCH": an issue in flight and its repo chips.
    @ViewBuilder private var declared: some View {
        Text(skin.labelCased("Issues declare the repos they touch")).citadelFont("t10", weight: "semibold")
            .foregroundStyle(skin.color(skin.text.muted))
        if let (issue, names) = page.declared[project.id] {
            DeclaredRow(issue: issue, repos: names)
        }
        Text(
            "Default: the primary repo. The PO / Lead sets repos at planning; an agent that needs another repo mid-run asks via MCP and the Lead approves."
        )
        .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).fixedSize(horizontal: false, vertical: true)
    }
}

private struct DeclaredRow: View {
    let issue: IssueInfo
    let repos: [String]
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        let count = repos.count
        HStack(spacing: skin.size.s8) {
            Text(issue.key).citadelFont("t12", mono: true).foregroundStyle(theme.accentSecondary)
            Text(issue.title).citadelFont("t12").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
            Text("repos").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
            ForEach(repos, id: \.self) { AinkradChip(label: $0, systemName: "arrow.triangle.branch") }
            Spacer(minLength: skin.size.s8)
            Text(
                "→ \(count) worktree\(count == 1 ? "" : "s") · \(count) PR\(count == 1 ? "" : "s") · done when \(count == 1 ? "it merges" : count == 2 ? "both merge" : "all merge")"
            )
            .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
        }
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s8)
        .background(
            skin.color(skin.palette.white).opacity(skin.opacity.o03),
            in: RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous))
    }
}

/// One repo: name, ★ primary, stack; URL, default branch, forge and the vault reference; its four commands.
private struct RepoCard: View {
    let store: CitadelStore
    let repo: RepoInfo
    let project: Int64
    let stack: String?
    @State private var confirmsRemove = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            HStack(spacing: skin.size.s10) {
                Text(repo.name).citadelFont("t13", weight: "bold", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary))
                if repo.isPrimary {
                    AinkradBadge(text: "★ Primary", status: .warning)
                } else {
                    AinkradIconButton(systemName: "star", size: skin.size.s18, tooltip: "Make primary") {
                        store.makePrimary(repo)
                    }
                    .bare()
                }
                if let stack, !stack.isEmpty {
                    Text(stack).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
                }
                Spacer(minLength: skin.size.s8)
                if repo.isPrimary {
                    Text("click ★ on another repo to make it primary").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
            }
            HStack(spacing: skin.size.s10) {
                Text(repo.shortURL).citadelFont("t12").foregroundStyle(theme.accentSecondary).lineLimit(1)
                    .truncationMode(.middle).layoutPriority(-1)
                Text("⑂ \(repo.defaultBranch)").citadelFont("t12", mono: true)
                    .foregroundStyle(skin.color(skin.text.primary)).help("Default branch").fixedSize()
                if let forge = repo.forgeKind {
                    AinkradBadge(text: forge == "gitlab" ? "GitLab" : "GitHub", status: .neutral).fixedSize()
                }
                if !repo.inUseBy.isEmpty {
                    AinkradBadge(text: "in use by \(repo.inUseBy.joined(separator: ", "))", tint: theme.accentSecondary)
                        .fixedSize()
                        .help("Issues working it now")
                }
                if let vault = repo.vaultLine {
                    Label(vault, systemImage: "lock.fill").labelStyle(.titleAndIcon).citadelFont("t11", mono: true)
                        .foregroundStyle(skin.color(skin.text.faint)).fixedSize()
                }
                Spacer(minLength: skin.size.s8)
                AinkradIconButton(systemName: "xmark", size: skin.size.s18, tooltip: "Remove repository") {
                    confirmsRemove = true
                }
                .bare()
            }
            HStack(alignment: .top, spacing: skin.size.s6) {
                ForEach(repo.commands, id: \.label) { command in
                    CommandField(
                        store: store, repo: repo, project: project, label: command.label, value: command.command)
                }
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .ainkradConfirmDialog(
            isPresented: $confirmsRemove, title: "Remove \(repo.name)?",
            message: "Its worktrees are removed with it. Citadel refuses while an open issue still touches it.",
            confirmTitle: "Remove", isDestructive: true
        ) { store.removeRepo(repo) }
    }
}

/// One command input: edited in place, saved on Return (`updateRepo`), the border flashing green once saved.
private struct CommandField: View {
    let store: CitadelStore
    let repo: RepoInfo
    let project: Int64
    let label: String
    let value: String?
    @State private var text = ""
    @State private var saved = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s2) {
            Text(skin.labelCased(label)).citadelFont("t9_5", weight: "semibold").foregroundStyle(
                skin.color(skin.text.muted))
            AinkradTextField(text: $text, placeholder: "none").compact().monospaced().onSubmit(commit)
                .overlay(
                    RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous)
                        .strokeBorder(skin.color(skin.palette.success).opacity(saved ? skin.opacity.o60 : 0))
                )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .onAppear { text = value ?? "" }
        .onChange(of: value) { _, new in text = new ?? "" }
    }

    private func commit() {
        let next = text.trimmingCharacters(in: .whitespaces)
        guard next != (value ?? "") else { return }
        var edited = repo
        switch label {
        case "Build": edited.build = next.isEmpty ? nil : next
        case "Test": edited.test = next.isEmpty ? nil : next
        case "Lint": edited.lint = next.isEmpty ? nil : next
        default: edited.format = next.isEmpty ? nil : next
        }
        store.saveCommands(edited, project: project, label: label) { ok in
            saved = ok
            Task {
                try? await Task.sleep(for: .milliseconds(900))
                saved = false
            }
        }
    }
}

/// "＋ Add repository": name, URL, default branch, forge and the vault reference of its token. From API minor 18
/// it is checked first (the URL resolves, the token can push and open a PR, the stack is read) and a repo that
/// fails the check is never created; an older server checks the URL and token itself when it saves.
private struct AddRepoSheet: View {
    @Binding var isPresented: Bool
    let probes: Bool
    let probe: (String, String, String, String, @escaping @MainActor (Result<RepoProbe, ServerAnswer>) -> Void) -> Void
    let add: (String, String, String, String, String, RepoProbe?) -> Void
    @State private var name = ""
    @State private var url = ""
    @State private var branch = "development"
    @State private var forge = "github"
    @State private var token = ""
    @State private var checking = false
    @State private var found: Result<RepoProbe, ServerAnswer>?
    @Environment(\.ainkradSkin) private var skin

    private var passed: RepoProbe? { if case .success(let probe) = found, probe.passes { probe } else { nil } }

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Add repository").citadelFont("t15", weight: "semibold")
            AinkradFormRow(title: "Name") { AinkradTextField(text: $name, placeholder: "citadel") }
            AinkradFormRow(title: "URL") { AinkradTextField(text: $url, placeholder: "https://github.com/…") }
            AinkradFormRow(title: "Default branch") { AinkradTextField(text: $branch, placeholder: "development") }
            AinkradFormRow(title: "Forge") {
                AinkradSegmentedPicker(items: ["github", "gitlab"], selection: $forge) {
                    $0 == "github" ? "GitHub" : "GitLab"
                }
                .fixedSize()
            }
            AinkradFormRow(title: "Token", help: "A reference into the server vault — never the token itself.") {
                AinkradTextField(text: $token, placeholder: "github-ainkradhq")
            }
            if probes, checking || found != nil { stages }
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { isPresented = false }.fixedSize()
                if probes, passed == nil {
                    AinkradButton(title: checking ? "Checking…" : "Check") { check() }
                        .fixedSize().disabled(name.isEmpty || url.isEmpty || checking)
                } else {
                    AinkradButton(title: "Add") {
                        add(name, url, branch, forge, token, passed)
                        isPresented = false
                    }
                    .fixedSize()
                    .disabled(name.isEmpty || url.isEmpty)
                }
            }
        }
        .padding(skin.size.s20)
        .frame(width: skin.size.s480)
        .onChange(of: [name, url, forge, token]) { _, _ in found = nil }
    }

    /// Resolve → token → stack, each with what the server found.
    private var stages: some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            Text("Checked first: the URL resolves and the token can push a branch and open a PR.")
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            AinkradStepTrail(steps: steps)
            if case .success(let probe) = found, let note = probe.note {
                Text(note).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
            }
            if case .failure(let answer) = found {
                Text(answer.message).citadelFont("t11").foregroundStyle(skin.color(skin.palette.danger))
            }
        }
    }

    private var steps: [AinkradTrailStep] {
        guard case .success(let probe) = found else {
            if case .failure = found { return [AinkradTrailStep(label: "Resolve", state: .bad)] }
            return [AinkradTrailStep(label: "Resolving…", state: .warn)]
        }
        let token: AinkradTrailStep =
            switch probe.canPush {
            case true?: AinkradTrailStep(label: "Token can push", detail: "opens a PR")
            case false?: AinkradTrailStep(label: "Token can't push", state: .bad)
            case nil: AinkradTrailStep(label: "Token not checked", state: .warn)
            }
        return [
            AinkradTrailStep(
                label: probe.reachable ? "Resolved" : "Not reachable", state: probe.reachable ? .ok : .bad,
                detail: probe.defaultBranch.map { "⑂ \($0)" }),
            token,
            AinkradTrailStep(
                label: probe.stack.isEmpty ? "Stack unknown" : probe.stack, state: probe.stack.isEmpty ? .warn : .ok),
        ]
    }

    private func check() {
        checking = true
        found = nil
        probe(name, url, forge, token) { result in
            checking = false
            found = result
            if case .success(let probe) = result, probe.passes, let branch = probe.defaultBranch {
                self.branch = branch
            }
        }
    }
}
