import AinkradAppKit
import SwiftUI

/// The requirement drawer's header (`.rqd .dr-h`): "‹ Back" when something is under the current view, and the crumb
/// trail with the current view in bold.
struct RequirementDrawerHeader: View {
    let model: CompanyModel
    let requirement: RequirementInfo
    @Environment(\.ainkradSkin) private var skin

    private var page: RequirementsPage { model.requirementsPage }

    var body: some View {
        let stack = page.drawer
        HStack(spacing: skin.size.s10) {
            if stack.count > 1 {
                AinkradTapArea(help: "Back", action: { page.drawer.removeLast() }) {
                    Text("‹ \(title(stack[stack.count - 2]))").citadelFont("t12")
                        .foregroundStyle(skin.color(skin.palette.accentPrimary))
                        .padding(.horizontal, skin.size.s12)
                        .frame(height: skin.size.s30)
                        .background(
                            skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o14),
                            in: RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous))
                }
            }
            HStack(spacing: skin.size.s6) {
                ForEach(Array(stack.enumerated()), id: \.offset) { index, view in
                    if index > 0 { Text("›") }
                    Text(index < stack.count - 1 && isArtifact(view) ? "Preview" : title(view))
                        .fontWeight(index == stack.count - 1 ? .semibold : .regular)
                        .foregroundStyle(skin.color(index == stack.count - 1 ? skin.text.primary : skin.text.faint))
                        .lineLimit(1)
                }
            }
            .citadelFont("t12")
            .foregroundStyle(skin.color(skin.text.faint))
        }
    }

    private func isArtifact(_ view: RequirementDrawer) -> Bool {
        if case .artifact = view { true } else { false }
    }

    private func title(_ view: RequirementDrawer) -> String {
        switch view {
        case .plan: "Plan"
        case .artifacts: "Artifacts"
        case .artifact(let id): model.requirementArtifacts(requirement).first { $0.id == id }?.name ?? "Artifact"
        }
    }
}

/// The drawer's body for its current view, rising in from the right on each change (`rqdIn .28s`).
struct RequirementDrawerBody: View {
    let store: CitadelStore
    let model: CompanyModel
    let requirement: RequirementInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Group {
            switch model.requirementsPage.drawer.last {
            case .plan?: RequirementPlanView(store: store, model: model, requirement: requirement)
            case .artifacts?: artifacts
            case .artifact(let id)?: ArtifactPreview(store: store, model: model, requirement: requirement, id: id)
            case nil: EmptyView()
            }
        }
        .id(model.requirementsPage.drawer.last)
        .transition(reduceMotion ? .opacity : .opacity.combined(with: .offset(x: skin.size.s18)))
        .animation(
            reduceMotion ? nil : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.28)),
            value: model.requirementsPage.drawer)
    }

    @ViewBuilder private var artifacts: some View {
        let all = model.requirementArtifacts(requirement)
        let page = model.requirementsPage
        if all.isEmpty {
            AinkradEmptyState(
                icon: "square.3.layers.3d", title: "No artifacts yet",
                message: "Reports, screenshots and logs the agents publish for \(requirement.key) land here."
            )
            .padding(.vertical, skin.size.s60)
        } else {
            let kinds = Array(Set(all.map(\.kind))).sorted()
            let list = all.filter { page.artifactKind == nil || $0.kind == page.artifactKind }
            VStack(alignment: .leading, spacing: skin.size.s12) {
                HStack(spacing: skin.size.s12) {
                    VStack(alignment: .leading, spacing: skin.size.s1) {
                        Text(Wording.count(all.count, "artifact")).citadelFont("t14", weight: "semibold")
                            .foregroundStyle(skin.color(skin.text.primary))
                        Text("published by \(publishers(all)) for \(requirement.key)").citadelFont("t11")
                            .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                    }
                    Spacer(minLength: skin.size.s8)
                    AinkradButton(title: "All artifacts ⇱", style: .ghost) {
                        page.drawer = []
                        store.showArtifacts(requirement: requirement.id)
                    }
                    .borderless().secondaryAccent().compact().fixedSize()
                }
                AinkradGlideTabs(
                    [AinkradGlideTab("", title: "All", count: "\(all.count)")]
                        + kinds.map { kind in
                            AinkradGlideTab(kind, title: kind, count: "\(all.filter { $0.kind == kind }.count)")
                        },
                    selection: Binding(
                        get: { page.artifactKind ?? "" }, set: { page.artifactKind = $0.isEmpty ? nil : $0 }),
                    height: skin.size.s32)
                LazyVGrid(
                    columns: [GridItem(.flexible(), spacing: skin.size.s10), GridItem(.flexible())],
                    spacing: skin.size.s10
                ) {
                    ForEach(list) { artifact in
                        ArtifactCard(model: model, artifact: artifact) { page.drawer.append(.artifact(artifact.id)) }
                            .onAppear { store.loadPreview(artifact) }
                    }
                }
            }
        }
    }

    private func publishers(_ list: [ArtifactInfo]) -> String {
        var names: [String] = []
        for name in list.compactMap({ model.agent($0.agentID)?.name }) where !names.contains(name) {
            names.append(name)
        }
        return names.joined(separator: ", ")
    }
}

/// The drawer's pinned foot: on the plan while it waits, "Nothing starts until you approve." and the decision.
struct RequirementDrawerFooter: View {
    let store: CitadelStore
    let model: CompanyModel
    let requirement: RequirementInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        if model.requirementsPage.drawer.last == .plan, requirement.state == "plan_review",
            let approval = model.approvals.first(where: {
                $0.kind == "plan_approval" && $0.fields["requirement"] == String(requirement.id)
            })
        {
            HStack(spacing: skin.size.s8) {
                Text("Nothing starts until you approve.").citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.faint))
                Spacer(minLength: skin.size.s8)
                AinkradButton(title: "Ask for changes…", style: .secondary) {
                    model.requirementsPage.drawer = []
                    model.requirementsPage.askingChanges = true
                }
                .compact().fixedSize()
                AinkradButton(title: "Approve plan") {
                    model.requirementsPage.drawer = []
                    store.approvePlan(approval, requirement: requirement)
                }
                .compact().fixedSize()
            }
            .padding(.horizontal, skin.size.s16)
            .padding(.vertical, skin.size.s12)
            .background(skin.color(.palette("foreground", skin.opacity.o03)))
        }
    }
}

extension CompanyModel {
    /// What agents published for a requirement: its thread's artifacts, then any listed on it or its plan's issues.
    func requirementArtifacts(_ requirement: RequirementInfo) -> [ArtifactInfo] {
        var out: [ArtifactInfo] = []
        for item in requirementsPage.threads[requirement.id]?.items ?? [] {
            if case .artifact(let a) = item { out.append(a) }
        }
        let issues = Set(requirementsPage.plans[requirement.id]?.allTasks.map(\.issueID) ?? [])
        for artifact in artifactsPage.items
        where !out.contains(where: { $0.id == artifact.id })
            && (artifact.requirementID == requirement.id || artifact.issueID.map(issues.contains) == true)
        {
            out.append(artifact)
        }
        return out
    }
}

/// A drawer artifact card (`.pv-art`): a 130 pt preview — the image, a fading text excerpt or the log's first
/// lines — over the type tile, name and "issue · agent · when". Lifts with a blue rim on hover.
private struct ArtifactCard: View {
    let model: CompanyModel
    let artifact: ArtifactInfo
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        AinkradTapArea(help: artifact.name, action: open) {
            VStack(alignment: .leading, spacing: 0) {
                ArtifactBody(model: model, artifact: artifact, excerpt: true)
                    .frame(height: skin.size.s128)
                    .frame(maxWidth: .infinity)
                    .clipped()
                    .background(skin.color(.palette("black", skin.opacity.o25)))
                HStack(spacing: skin.size.s10) {
                    ArtifactTypeTile(artifact: artifact, size: skin.size.s28)
                    VStack(alignment: .leading, spacing: skin.size.s1) {
                        Text(artifact.name).citadelFont("t12", weight: "medium").lineLimit(1)
                            .foregroundStyle(skin.color(skin.text.primary))
                        Text(model.artifactByline(artifact)).citadelFont("t10_5").lineLimit(1)
                            .foregroundStyle(skin.color(skin.text.faint))
                    }
                }
                .padding(.horizontal, skin.size.s12)
                .padding(.vertical, skin.size.s10)
            }
            .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o05))))
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    hovering
                        ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o45)
                        : skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1)
            )
            .contentShape(shape)
        }
        .offset(y: hovering && !reduceMotion ? -skin.size.s3 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

extension CompanyModel {
    /// "CIT-61 · Sable · 30m ago".
    func artifactByline(_ artifact: ArtifactInfo) -> String {
        [
            issue(artifact.issueID)?.key, agent(artifact.agentID)?.name,
            "\(Fmt.age(Date().timeIntervalSince(artifact.createdAt))) ago",
        ].compactMap { $0 }.joined(separator: " · ")
    }
}

/// The type glyph tile (`.pv-ty`).
struct ArtifactTypeTile: View {
    let artifact: ArtifactInfo
    let size: CGFloat
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Image(systemName: artifact.isImage ? "photo" : artifact.isText ? "doc.text" : "doc")
            .citadelFont(size > skin.size.s30 ? "t16" : "t12")
            .foregroundStyle(skin.color(skin.palette.accentPrimary))
            .frame(width: size, height: size)
            .background(
                skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o14),
                in: RoundedRectangle(cornerRadius: size * 0.3, style: .continuous))
    }
}

/// An artifact's content: the image, its text (an excerpt fading out in cards), or a note that it only downloads.
struct ArtifactBody: View {
    let model: CompanyModel
    let artifact: ArtifactInfo
    var excerpt = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        if let image = model.artifactsPage.images[artifact.id] {
            Image(nsImage: image).resizable().aspectRatio(contentMode: excerpt ? .fill : .fit)
                .padding(excerpt ? skin.size.s8 : 0)
        } else if let text = model.artifactsPage.texts[artifact.id] {
            VStack(alignment: .leading) {
                Text(excerpt ? String(text.prefix(600)) : text)
                    .citadelFont(excerpt ? "t10" : "t12", mono: !artifact.isMarkdown)
                    .foregroundStyle(skin.color(skin.text.muted))
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .textSelection(.enabled)
                Spacer(minLength: 0)
            }
            .padding(excerpt ? skin.size.s12 : skin.size.s18)
            .mask(
                LinearGradient(
                    stops: [.init(color: .black, location: excerpt ? 0.6 : 1), .init(color: .clear, location: 1)],
                    startPoint: .top, endPoint: .bottom))
        } else {
            Text(artifact.isImage || artifact.isText ? "Loading preview…" : "No preview — download it to open.")
                .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }
}
