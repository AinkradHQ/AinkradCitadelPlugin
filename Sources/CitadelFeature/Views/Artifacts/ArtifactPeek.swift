import AinkradAppKit
import SwiftUI

/// The artifact peek drawer (`artDrawer`): ‹ k / n ›, the head, the large preview (click or Space for Quick Look),
/// Download · Open in Lore · Copy link · Quick Look, "Produced by" tiles with the hash, and the other files from the
/// same issue. Download writes through a save panel; the file is never opened or run here.
struct ArtifactPeek: View {
    let store: CitadelStore
    let model: CompanyModel
    let artifact: ArtifactInfo
    @State private var hoveringPreview = false
    @Environment(\.ainkradSkin) private var skin

    private var page: ArtifactsPage { model.artifactsPage }
    private var look: ArtifactTypeLook { ArtifactTypeLook(type: artifact.type) }
    private var tint: Color { look.hue.color(skin) }

    var body: some View {
        let list = model.filteredArtifacts
        let index = list.firstIndex { $0.id == artifact.id }
        let prev = index.flatMap { $0 > 0 ? list[$0 - 1] : nil }
        let next = index.flatMap { $0 + 1 < list.count ? list[$0 + 1] : nil }
        PeekDrawer(contentID: artifact.id, onClose: { page.selectedID = nil }) {
            DrawerCrumb(parts: ["Artifacts", look.plural])
        } trailing: {
            DrawerCloseButton(glyph: "chevron.left", size: skin.size.s28, isEnabled: prev != nil, filled: true) {
                page.selectedID = prev?.id
            }
            .keyboardShortcut(.leftArrow, modifiers: [])
            Text("\((index ?? 0) + 1) / \(list.count)").citadelFont("t11", mono: true)
                .foregroundStyle(skin.color(skin.text.faint))
            DrawerCloseButton(glyph: "chevron.right", size: skin.size.s28, isEnabled: next != nil, filled: true) {
                page.selectedID = next?.id
            }
            .keyboardShortcut(.rightArrow, modifiers: [])
        } content: {
            VStack(alignment: .leading, spacing: skin.size.s12) {
                head
                preview
                actions
                provenance
                siblings
            }
        } foot: {
            EmptyView()
        }
        .onAppear { store.loadPreview(artifact) }
        .onChange(of: artifact.id) { _, _ in store.loadPreview(artifact) }
    }

    private var head: some View {
        HStack(spacing: skin.size.s12) {
            IconTile(systemName: look.icon, tint: tint, size: skin.size.s40, radius: skin.size.s12)
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text(artifact.name).citadelFont("t16", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(1)
                Text(Self.meta(artifact, model: model)).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            }
        }
    }

    /// "Report · 2.1 KB · 1440×900 · 11:40 · 1 secret redacted" (no version: MISSING S10).
    static func meta(_ artifact: ArtifactInfo, model: CompanyModel, withTime: Bool = true) -> String {
        var parts = [ArtifactTypeLook(type: artifact.type).singular, ScopedSetting.bytes(artifact.size)]
        if let image = model.artifactsPage.images[artifact.id] {
            parts.append("\(Int(image.size.width))×\(Int(image.size.height))")
        }
        if withTime {
            parts.append("v1")
            parts.append(ArtifactsWhen.short(artifact.createdAt))
        }
        if artifact.redactions > 0 { parts.append(Wording.count(artifact.redactions, "secret") + " redacted") }
        return parts.joined(separator: " · ")
    }

    private var preview: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        return AinkradTapArea(help: "Quick Look (Space)", action: { page.quickLookID = artifact.id }) {
            ArtifactPreviewBody(model: model, artifact: artifact, size: .drawer)
                .frame(maxWidth: .infinity, alignment: .topLeading)
                .frame(height: artifact.isImage ? skin.size.s300 : nil)
                .frame(maxHeight: skin.size.s360, alignment: .top)
                .clipped()
                .background(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                tint.opacity(skin.opacity.o10), skin.color(.palette("background", skin.opacity.o90)),
                            ],
                            startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o22), lineWidth: 1))
                .clipShape(shape)
                .overlay(alignment: .bottomTrailing) {
                    HStack(spacing: skin.size.s6) {
                        Image(systemName: "plus.magnifyingglass")
                        Text("Quick Look")
                    }
                    .citadelFont("t11")
                    .foregroundStyle(skin.color(.palette("foreground", 1)))
                    .padding(.horizontal, skin.size.s10)
                    .frame(height: skin.size.s28)
                    .background(
                        skin.color(.palette("black", skin.opacity.o80)),
                        in: RoundedRectangle(cornerRadius: skin.size.s9)
                    )
                    .padding(skin.size.s12)
                    .opacity(hoveringPreview ? 1 : 0)
                    .offset(y: hoveringPreview ? 0 : skin.size.s6)
                }
                .contentShape(shape)
        }
        .onHover { hoveringPreview = $0 }
        .animation(
            skin.animation(AinkradAnimationToken(curve: "spring", response: 0.25, damping: 0.7)), value: hoveringPreview
        )
    }

    private var actions: some View {
        HStack(spacing: skin.size.s6) {
            AinkradDockButton("Download", systemImage: "arrow.down.to.line") { store.download(artifact) }
            // TODO(citadel#lore-open): hand the file to Lore once the host has a cross-plugin open intent.
            AinkradDockButton("Open in Lore", systemImage: "arrow.up.forward.square") {}
                .ainkradTooltip("Needs the host's cross-plugin open (not yet available)")
            AinkradDockButton("Copy link", systemImage: "doc.on.doc") {
                store.copyLink(artifact)
                store.toast(AinkradRichToast(title: "Link copied", body: artifact.name, status: .success))
            }
            AinkradDockButton("Quick Look", systemImage: "magnifyingglass", tone: .primary) {
                page.quickLookID = artifact.id
            }
        }
    }

    private var provenance: some View {
        let issue = model.issue(artifact.issueID)
        let requirementID = artifact.requirementID ?? issue?.requirementID
        let requirement = model.requirements.first { $0.id == requirementID }
        let accent = skin.color(skin.palette.accentSecondary)
        return RunPanel {
            RunCardHead(title: "Produced by")
            LazyVGrid(
                columns: [GridItem(.flexible(), spacing: skin.size.s8), GridItem(.flexible())], spacing: skin.size.s8
            ) {
                if let agent = model.agent(artifact.agentID) {
                    ContextTile(
                        label: "Agent", value: Text("\(agent.name) · \(agent.role)"),
                        action: { store.open(.agent(agent.id)) }
                    ) {
                        AgentFigure(agent: agent, model: model, size: skin.size.s22)
                            .frame(width: skin.size.s32, height: skin.size.s32)
                            .background(
                                tint.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s10))
                    }
                }
                if let run = artifact.runID {
                    ContextTile(
                        icon: "play", tint: tint, label: "Run", value: Text("#\(run)").monospaced(),
                        action: {
                            page.selectedID = nil
                            store.open(.run(run))
                        })
                }
                if let issue {
                    ContextTile(
                        icon: "text.alignleft", tint: tint, label: "Issue",
                        value: Text(issue.key).foregroundStyle(accent) + Text(" \(issue.title)"))
                }
                if let requirement {
                    ContextTile(
                        icon: "list.bullet", tint: tint, label: "Requirement",
                        value: Text(requirement.key).foregroundStyle(accent) + Text(" \(requirement.title)"),
                        action: { store.goRequirement(requirement.id) })
                }
            }
            HStack(spacing: skin.size.s8) {
                Image(systemName: "key").citadelFont("t11")
                Text("sha256 \(ArtifactInfo.shortHash(artifact.sha256)) · \(artifact.mime)").citadelFont(
                    "t11", mono: true
                )
                .textSelection(.enabled)
            }
            .foregroundStyle(skin.color(skin.text.faint))
        }
    }

    @ViewBuilder private var siblings: some View {
        let others = page.items.filter { $0.id != artifact.id && $0.issueID != nil && $0.issueID == artifact.issueID }
        if !others.isEmpty, let issue = model.issue(artifact.issueID) {
            RunPanel {
                RunCardHead(title: "Also from \(issue.key)", aside: "\(others.count)")
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: skin.size.s150), spacing: skin.size.s8)],
                    spacing: skin.size.s8
                ) {
                    ForEach(others) { other in
                        SiblingCard(model: model, artifact: other) { page.selectedID = other.id }
                            .onAppear { store.loadPreview(other) }
                    }
                }
            }
        }
    }
}

/// `.atd-sib`: an 80 pt mini preview and the name; lifts and takes its colour on hover.
private struct SiblingCard: View {
    let model: CompanyModel
    let artifact: ArtifactInfo
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let look = ArtifactTypeLook(type: artifact.type)
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        AinkradTapArea(action: action) {
            VStack(alignment: .leading, spacing: 0) {
                ArtifactPreviewBody(model: model, artifact: artifact, size: .sibling)
                    .frame(maxWidth: .infinity)
                    .frame(height: skin.size.s80)
                    .clipped()
                    .background(skin.color(.palette("background", skin.opacity.o60)))
                HStack(spacing: skin.size.s6) {
                    Image(systemName: look.icon).citadelFont("t10").foregroundStyle(look.hue.color(skin))
                    Text(artifact.name).citadelFont("t11").foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                }
                .padding(.horizontal, skin.size.s9)
                .padding(.vertical, skin.size.s7)
            }
            .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o05))))
            .overlay(
                shape.strokeBorder(
                    hovering
                        ? look.hue.color(skin).opacity(skin.opacity.o45)
                        : skin.color(.palette("foreground", skin.opacity.o06)),
                    lineWidth: 1)
            )
            .clipShape(shape)
            .contentShape(shape)
        }
        .offset(y: hovering && !reduceMotion ? -skin.size.s2 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// Quick Look (`artLightbox`): a full-pane viewer over a blurred scrim — name and type, ‹ › and ✕, the document
/// centred, the image fitted. Esc, ✕ and the scrim close it.
struct ArtifactQuickLook: View {
    let store: CitadelStore
    let model: CompanyModel
    let artifact: ArtifactInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let page = model.artifactsPage
        let list = model.filteredArtifacts
        let index = list.firstIndex { $0.id == artifact.id }
        let prev = index.flatMap { $0 > 0 ? list[$0 - 1] : nil }
        let next = index.flatMap { $0 + 1 < list.count ? list[$0 + 1] : nil }
        let tint = ArtifactTypeLook(type: artifact.type).hue.color(skin)
        let shape = RoundedRectangle(cornerRadius: skin.size.s22, style: .continuous)
        GeometryReader { geo in
            ZStack {
                skin.color(.palette("black", skin.opacity.o60))
                    .background(.ultraThinMaterial)
                    .contentShape(Rectangle())
                    .onTapGesture { page.quickLookID = nil }
                VStack(spacing: 0) {
                    HStack(spacing: skin.size.s10) {
                        Text(artifact.name).citadelFont("t14", weight: "bold").foregroundStyle(
                            skin.color(skin.text.primary))
                        Text(ArtifactPeek.meta(artifact, model: model, withTime: false)).citadelFont("t11")
                            .foregroundStyle(skin.color(skin.text.faint))
                        Spacer(minLength: skin.size.s8)
                        if let prev {
                            DrawerCloseButton(glyph: "chevron.left", size: skin.size.s28, filled: true) {
                                page.quickLookID = prev.id
                                store.loadPreview(prev)
                            }
                            .keyboardShortcut(.leftArrow, modifiers: [])
                        }
                        if let next {
                            DrawerCloseButton(glyph: "chevron.right", size: skin.size.s28, filled: true) {
                                page.quickLookID = next.id
                                store.loadPreview(next)
                            }
                            .keyboardShortcut(.rightArrow, modifiers: [])
                        }
                        DrawerCloseButton { page.quickLookID = nil }
                    }
                    .padding(.horizontal, skin.size.s16)
                    .padding(.vertical, skin.size.s14)
                    ScrollView {
                        ArtifactPreviewBody(model: model, artifact: artifact, size: .quickLook)
                            .frame(maxWidth: .infinity, minHeight: artifact.isImage ? geo.size.height * 0.7 : nil)
                            .id(artifact.id)
                    }
                    .background(
                        skin.color(.palette("background", skin.opacity.o60)),
                        in: RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
                    )
                    .clipShape(RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous))
                    .padding(.horizontal, skin.size.s16)
                    .padding(.bottom, skin.size.s16)
                }
                .background(shape.fill(skin.color(.palette("surface", skin.opacity.o96))))
                .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o30), lineWidth: 1))
                .clipShape(shape)
                .shadow(color: skin.color(.palette("black", skin.opacity.o60)), radius: skin.size.s50, y: skin.size.s40)
                .padding(.vertical, geo.size.height * 0.06)
                .padding(.horizontal, geo.size.width * 0.08)
            }
        }
        .onAppear { store.loadPreview(artifact) }
    }
}
