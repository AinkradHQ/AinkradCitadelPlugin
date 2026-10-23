import AinkradAppKit
import SwiftUI

/// Screen 13: every file, report and screenshot the company's agents published — grouped by day, filtered by
/// requirement, type, agent and issue — beside the selected one's preview and where it came from. Storage use
/// against the company's quota is in the header (decision #47).
struct ArtifactsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var page: ArtifactsPage { model.artifactsPage }
    private var items: [ArtifactInfo] { model.filteredArtifacts }
    private var selected: ArtifactInfo? { page.items.first { $0.id == page.selectedID } ?? items.first }

    var body: some View {
        HStack(spacing: 0) {
            VStack(alignment: .leading, spacing: 0) {
                PaneTitle(
                    title: "Artifacts",
                    crumb: Text(model.artifactsCrumb(company: store.company?.name ?? "this company", now: Date()))
                        .foregroundStyle(skin.color(skin.text.muted))
                ) {
                    AinkradSegmentedPicker(
                        items: [true, false], selection: Binding(get: { page.isGrid }, set: { page.isGrid = $0 }),
                        label: { $0 ? "Grid" : "List" }
                    )
                    .fixedSize()
                }
                filters
                content.offlineDimmed()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            Group {
                if let selected {
                    ArtifactPreviewPane(store: store, model: model, artifact: selected).id(selected.id)
                        .transition(.opacity)
                } else {
                    Color.clear
                }
            }
            .frame(width: skin.size.s420)
            .frame(maxHeight: .infinity)
            .background(theme.surface.opacity(skin.opacity.o20))
            .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: selected?.id)
        }
        .onAppear { store.loadArtifacts() }
    }

    private var filters: some View {
        let all = page.items
        let kinds: [String?] = [nil] + Array(Set(all.map(\.kind))).sorted()
        let agents: [Int64?] = [nil] + Array(Set(all.compactMap(\.agentID))).sorted()
        let issues: [Int64?] = [nil] + Array(Set(all.compactMap(\.issueID))).sorted()
        return HStack(spacing: skin.size.s8) {
            if let id = page.filter.requirementID {
                AinkradChip(
                    label: "Requirement: \(model.requirements.first { $0.id == id }?.key ?? "R-\(id)")",
                    systemName: "rhombus.fill", onRemove: { page.filter.requirementID = nil }
                )
                .fixedSize()
            }
            AinkradSelect(
                items: kinds, selection: Binding(get: { page.filter.kind }, set: { page.filter.kind = $0 }),
                label: { $0 ?? "All types" }
            )
            .fixedSize()
            AinkradSelect(
                items: agents, selection: Binding(get: { page.filter.agentID }, set: { page.filter.agentID = $0 }),
                label: { id in id.map { model.agent($0)?.name ?? "Agent \($0)" } ?? "Agent" }
            )
            .fixedSize()
            AinkradSelect(
                items: issues, selection: Binding(get: { page.filter.issueID }, set: { page.filter.issueID = $0 }),
                label: { id in id.map { model.issue($0)?.key ?? "#\($0)" } ?? "Issue" }
            )
            .fixedSize()
            Spacer(minLength: skin.size.s8)
            Text("\(items.count) artifact\(items.count == 1 ? "" : "s") · newest first").citadelFont("t11")
                .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1).layoutPriority(1)
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.bottom, skin.size.s10)
    }

    @ViewBuilder private var content: some View {
        if !page.isLoaded || (page.items.isEmpty && page.usage == nil) {
            VStack(spacing: skin.size.s10) {
                ForEach(0..<3, id: \.self) { _ in AinkradSkeletonRow(widthFraction: 0.8) }
            }
            .padding(.horizontal, skin.size.s20)
            Spacer(minLength: 0)
        } else if items.isEmpty {
            AinkradEmptyState(
                icon: "doc.text", title: page.items.isEmpty ? "No artifacts yet" : "Nothing matches",
                message: page.items.isEmpty
                    ? "Reports, screenshots and files agents publish land here — no conversation needed to find them."
                    : "Clear a filter to see more."
            )
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: skin.size.s10) {
                    ForEach(ArtifactGroup.groups(items, now: Date())) { group in
                        Text(skin.labelCased(group.title)).citadelFont("t10", weight: "semibold")
                            .foregroundStyle(skin.color(skin.text.muted))
                            .padding(.top, skin.size.s4)
                        if page.isGrid { grid(group.items) } else { rows(group.items) }
                    }
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.bottom, skin.size.s16)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: items.map(\.id))
            }
        }
    }

    private func grid(_ list: [ArtifactInfo]) -> some View {
        LazyVGrid(
            columns: Array(repeating: GridItem(.flexible(), spacing: skin.size.s10), count: 3),
            alignment: .leading, spacing: skin.size.s10
        ) {
            ForEach(list) { artifact in
                AinkradFileThumbnail(
                    name: artifact.name, typeLabel: artifact.typeLabel(imageSize: page.images[artifact.id]?.size),
                    agent: model.agent(artifact.agentID)?.name, references: model.references(artifact),
                    detail: detail(artifact), isSelected: artifact.id == selected?.id,
                    action: { page.selectedID = artifact.id },
                    preview: { ArtifactPreviewThumb(model: model, artifact: artifact) },
                    avatar: { avatar(artifact) }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear { store.loadPreview(artifact) }
            }
        }
    }

    private func rows(_ list: [ArtifactInfo]) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s2) {
            ForEach(list) { artifact in
                AinkradListRow(
                    isSelected: artifact.id == selected?.id, onTap: { page.selectedID = artifact.id },
                    leading: { avatar(artifact) }, title: artifact.name,
                    subtitle: ([model.agent(artifact.agentID)?.name] + model.references(artifact).map(Optional.some)
                        + [detail(artifact)]).compactMap { $0 }.joined(separator: " · "),
                    trailing: {
                        Text(artifact.typeLabel()).citadelFont("t10", mono: true)
                            .foregroundStyle(skin.color(skin.text.faint))
                    })
            }
        }
    }

    @ViewBuilder private func avatar(_ artifact: ArtifactInfo) -> some View {
        if let agent = model.agent(artifact.agentID) { AgentFigure(agent: agent, model: model, size: skin.size.s18) }
    }

    /// "run #428" when it came from a run with no requirement to name, nothing when it names both an issue and a
    /// requirement, else its time.
    private func detail(_ artifact: ArtifactInfo) -> String? {
        if let run = artifact.runID, artifact.requirementID == nil { return "run #\(run)" }
        if model.references(artifact).count > 1 { return nil }
        return RequirementThreadView.time(artifact.createdAt)
    }
}

/// A card's preview well: the first lines of a text file, the image, or an icon for anything else.
struct ArtifactPreviewThumb: View {
    let model: CompanyModel
    let artifact: ArtifactInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        Group {
            if let image = model.artifactsPage.images[artifact.id] {
                Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
            } else if let text = model.artifactsPage.texts[artifact.id] {
                Text(Self.firstLines(text)).citadelFont("t9", mono: !artifact.isMarkdown).lineLimit(5)
                    .foregroundStyle(skin.color(skin.text.muted)).lineSpacing(skin.size.s1)
                    .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                    .padding(.horizontal, skin.size.s10).padding(.top, skin.size.s8)
            } else {
                Text(artifact.ext == "json" ? "{ }" : artifact.isImage ? "◫" : "⇩").citadelFont("t28")
                    .foregroundStyle(theme.accentSecondary)
            }
        }
        .frame(maxWidth: .infinity)
        .frame(height: skin.size.s96)
        .clipped()
    }

    /// The first five non-empty lines, markdown marks dropped (the type tag covers the rest).
    static func firstLines(_ text: String) -> String {
        text.split(separator: "\n", omittingEmptySubsequences: true).prefix(5)
            .map {
                $0.replacingOccurrences(of: "**", with: "").trimmingCharacters(in: CharacterSet(charactersIn: "#|-* "))
            }
            .joined(separator: "\n")
    }
}
