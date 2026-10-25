import AinkradAppKit
import SwiftUI

/// The Artifacts screen (prototype `artifacts.js`): every report, file and screenshot agents published — type tiles,
/// agent and requirement pickers, Grid / List by day — with a peek drawer (‹ ›, provenance, siblings) and Quick Look.
/// Storage use against the company's quota is in the head (decision #47).
struct ArtifactsView: View {
    let store: CitadelStore
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @Environment(\.citadelOffline) private var offline

    private var page: ArtifactsPage { model.artifactsPage }
    private var items: [ArtifactInfo] { model.filteredArtifacts }

    var body: some View {
        ZStack {
            VStack(alignment: .leading, spacing: 0) {
                head
                filters.zIndex(2)
                content
                    .overlay {
                        if page.openPicker != nil {
                            Color.clear.contentShape(Rectangle()).onTapGesture { page.openPicker = nil }
                        }
                    }
                    .offlineDimmed()
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
            if let id = page.selectedID, let artifact = page.items.first(where: { $0.id == id }) {
                ArtifactPeek(store: store, model: model, artifact: artifact)
            }
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: page.selectedID == nil)
        .animation(reduceMotion ? nil : skin.animation(skin.motion.hover), value: page.openPicker)
        .onAppear { store.loadArtifacts() }
        .background {
            // Space opens Quick Look on the peeked artifact, or the first one.
            AinkradTapArea(action: {
                page.quickLookID = page.quickLookID == nil ? (page.selectedID ?? items.first?.id) : nil
            }) { Color.clear }
            .keyboardShortcut(.space, modifiers: [])
            .opacity(0)
        }
    }

    // MARK: - Head

    private var head: some View {
        HStack(alignment: .top, spacing: skin.size.s10) {
            VStack(alignment: .leading, spacing: skin.size.s2) {
                Text("Artifacts").citadelFont("t15", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                HStack(spacing: skin.size.s6) {
                    (offline?.crumb
                        ?? Text(model.artifactsCrumb(company: store.company?.name ?? "this company", now: Date()))
                        .foregroundStyle(skin.color(skin.text.muted)))
                        .font(skin.font(AinkradFontToken(sizeKey: "t11"), typography: typo)).lineLimit(1)
                    if let usage = page.usage, usage.quota > 0, offline?.crumb == nil {
                        AinkradBudgetBar(
                            label: "Storage", value: Double(usage.used), limit: Double(usage.quota),
                            warnFraction: model.warnFraction, showsHardLimit: false
                        )
                        .frame(width: skin.size.s90)
                    }
                }
            }
            Spacer(minLength: skin.size.s10)
            let accent = skin.color(skin.palette.accentSecondary)
            DockToggle("Grid", systemImage: "square.grid.2x2", isOn: page.isGrid, onTint: accent) { page.isGrid = true }
            DockToggle("List", systemImage: "list.bullet", isOn: !page.isGrid, onTint: accent) { page.isGrid = false }
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.top, skin.size.s14)
        .padding(.bottom, skin.size.s10)
    }

    // MARK: - Filters

    private var filters: some View {
        let all = page.items
        let tiles =
            [
                TypeTile(
                    id: "", label: "All", icon: ArtifactTypeLook(type: "").icon, count: all.count,
                    tint: Hue.slate.color(skin))
            ]
            + ArtifactTypeLook.tiles.map { type in
                let look = ArtifactTypeLook(type: type)
                return TypeTile(
                    id: type, label: look.plural, icon: look.icon, count: all.filter { $0.type == type }.count,
                    tint: look.hue.color(skin))
            }
        return HStack(spacing: skin.size.s8) {
            TypeTileBar(tiles: tiles, selection: page.filter.type ?? "") { page.filter.type = $0.isEmpty ? nil : $0 }
            ArtifactAgentPicker(model: model, page: page)
            ArtifactRequirementPicker(model: model, page: page)
        }
        .padding(.horizontal, skin.size.s20)
        .padding(.bottom, skin.size.s12)
    }

    // MARK: - Content

    @ViewBuilder private var content: some View {
        if !page.isLoaded || (page.items.isEmpty && page.usage == nil) {
            VStack(spacing: skin.size.s10) {
                ForEach(0..<3, id: \.self) { _ in AinkradSkeletonRow(widthFraction: 0.8) }
            }
            .padding(.horizontal, skin.size.s20)
            Spacer(minLength: 0)
        } else if items.isEmpty {
            VStack(spacing: skin.size.s10) {
                AinkradEmptyState(
                    icon: "doc.text", title: page.items.isEmpty ? "No artifacts yet" : "No artifacts match",
                    message:
                        "Agents publish reports, specs and screenshots with publish_artifact; they land here.")
                if !page.items.isEmpty {
                    AinkradDockButton("Clear filters", height: skin.size.s26) {
                        page.filter = ArtifactFilter()
                    }
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s20) {
                    ForEach(ArtifactGroup.groups(items, now: Date())) { group in
                        VStack(alignment: .leading, spacing: skin.size.s10) {
                            RunsSectionHead(title: group.title, count: group.items.count)
                            if page.isGrid { grid(group.items) } else { list(group.items) }
                        }
                    }
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.top, skin.size.s2)
                .padding(.bottom, skin.size.s20)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: items.map(\.id))
            }
        }
    }

    private func grid(_ list: [ArtifactInfo]) -> some View {
        let newest = page.items.map(\.createdAt).max()
        return LazyVGrid(
            columns: [GridItem(.adaptive(minimum: skin.size.s220), spacing: skin.size.s14)], alignment: .leading,
            spacing: skin.size.s14
        ) {
            ForEach(list) { artifact in
                ArtifactGridCard(
                    model: model, artifact: artifact, isSelected: artifact.id == page.selectedID,
                    isFresh: artifact.createdAt == newest && Date().timeIntervalSince(artifact.createdAt) < 120,
                    action: { page.selectedID = artifact.id }
                )
                .transition(.move(edge: .top).combined(with: .opacity))
                .onAppear { store.loadPreview(artifact) }
            }
        }
    }

    private func list(_ list: [ArtifactInfo]) -> some View {
        VStack(spacing: skin.size.s2) {
            ForEach(list) { artifact in
                ArtifactRow(model: model, artifact: artifact, isSelected: artifact.id == page.selectedID) {
                    page.selectedID = artifact.id
                }
                .onAppear { store.loadPreview(artifact) }
            }
        }
        .padding(skin.size.s5)
        .background(
            RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
                .fill(skin.color(.palette("background", skin.opacity.o55)))
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
                .strokeBorder(skin.color(.palette("foreground", skin.opacity.o05)), lineWidth: 1))
    }
}

/// "Agent · Everyone": who published it.
struct ArtifactAgentPicker: View {
    let model: CompanyModel
    let page: ArtifactsPage
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let all = page.items
        let ids = Array(Set(all.compactMap(\.agentID))).sorted {
            (model.agent($0)?.name ?? "") < (model.agent($1)?.name ?? "")
        }
        let selected = model.agent(page.filter.agentID)
        RichPicker(
            caption: "Agent", value: selected?.name ?? "Everyone", isOn: selected != nil,
            isOpen: Binding(get: { page.openPicker == "agent" }, set: { page.openPicker = $0 ? "agent" : nil })
        ) {
            if let selected {
                AgentFigure(agent: selected, model: model, size: skin.size.s30)
            } else {
                Image(systemName: "person.2").citadelFont("t14")
            }
        } menu: {
            RichMenu(header: "Published by") {
                RichMenuRow(
                    title: "Everyone", subtitle: Wording.count(ids.count, "agent"), count: all.count,
                    isChecked: page.filter.agentID == nil, action: { pick(nil) }
                ) { RunAvatarStack(model: model, ids: Array(ids.prefix(4))) }
                RichMenuSeparator()
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    if let agent = model.agent(id) {
                        RichMenuRow(
                            title: agent.name, subtitle: agent.role, count: all.filter { $0.agentID == id }.count,
                            isChecked: page.filter.agentID == id, index: index + 1, action: { pick(id) }
                        ) { AgentFigure(agent: agent, model: model, size: skin.size.s28) }
                    }
                }
            }
        }
    }

    private func pick(_ id: Int64?) {
        page.filter.agentID = id
        page.openPicker = nil
    }
}

/// "Requirement · Any": the requirement it came from (its own, else its issue's).
struct ArtifactRequirementPicker: View {
    let model: CompanyModel
    let page: ArtifactsPage
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let all = page.items
        let requirementOf = { (a: ArtifactInfo) in a.requirementID ?? model.issue(a.issueID)?.requirementID }
        let ids = Array(Set(all.compactMap(requirementOf))).sorted(by: >)
        let selected = model.requirements.first { $0.id == page.filter.requirementID }
        RichPicker(
            caption: "Requirement", value: selected.map { "\($0.key) · \($0.title)" } ?? "Any", isOn: selected != nil,
            isOpen: Binding(
                get: { page.openPicker == "requirement" }, set: { page.openPicker = $0 ? "requirement" : nil })
        ) {
            Image(systemName: "list.bullet").citadelFont("t14")
        } menu: {
            RichMenu(header: "From requirement") {
                RichMenuRow(
                    title: "Any requirement", subtitle: Wording.count(ids.count, "requirement"), count: all.count,
                    isChecked: page.filter.requirementID == nil, action: { pick(nil) }
                ) {
                    Image(systemName: "list.bullet").citadelFont("t13").foregroundStyle(skin.color(skin.text.muted))
                        .frame(width: skin.size.s30, height: skin.size.s30)
                        .background(
                            skin.color(.palette("foreground", skin.opacity.o08)),
                            in: RoundedRectangle(cornerRadius: skin.size.s9))
                }
                RichMenuSeparator()
                ForEach(Array(ids.enumerated()), id: \.element) { index, id in
                    let requirement = model.requirements.first { $0.id == id }
                    RichMenuRow(
                        title: requirement?.title ?? "R-\(id)", subtitle: requirement?.key ?? "R-\(id)",
                        count: all.filter { requirementOf($0) == id }.count, isChecked: page.filter.requirementID == id,
                        index: index + 1, action: { pick(id) }
                    ) {
                        Text(requirement?.key ?? "R-\(id)").citadelFont("t10", weight: "semibold", mono: true)
                            .foregroundStyle(skin.color(.palette("foreground", 1)))
                            .frame(width: skin.size.s30, height: skin.size.s30)
                            .background(
                                LinearGradient(
                                    colors: [Hue.blue.color(skin), Hue.violet.color(skin)], startPoint: .topLeading,
                                    endPoint: .bottomTrailing),
                                in: RoundedRectangle(cornerRadius: skin.size.s9, style: .continuous))
                    }
                }
            }
        }
    }

    private func pick(_ id: Int64?) {
        page.filter.requirementID = id
        page.openPicker = nil
    }
}
