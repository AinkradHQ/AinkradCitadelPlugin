import AinkradAppKit
import SwiftUI

/// The selected artifact: Download (a save panel; the file is never opened or run here), Open in Lore, Copy link;
/// the preview — Markdown rendered, an image at fit size, other text as code — and where it came from.
struct ArtifactPreviewPane: View {
    let store: CitadelStore
    let model: CompanyModel
    let artifact: ArtifactInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    private var page: ArtifactsPage { model.artifactsPage }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: artifact.name, crumb: crumb) {
                HStack(spacing: skin.size.s8) {
                    AinkradIconButton(systemName: "arrow.down", size: skin.size.s30, tooltip: "Download…") {
                        store.download(artifact)
                    }
                    .outlineBox()
                    // TODO(citadel#lore-open): hand the file to Lore once the host has a cross-plugin open intent.
                    AinkradIconButton(systemName: "arrow.up.left.square", size: skin.size.s30, tooltip: "Open in Lore")
                    {}
                    .outlineBox().disabled(true)
                    AinkradIconButton(systemName: "doc.on.doc", size: skin.size.s30, tooltip: "Copy link") {
                        store.copyLink(artifact)
                    }
                    .outlineBox()
                }
            }
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s12) {
                    preview
                    provenance
                }
                .padding(.horizontal, skin.size.s16)
                .padding(.bottom, skin.size.s14)
            }
        }
        .onAppear { store.loadPreview(artifact) }
    }

    /// "report · 2.1 KB · 1 secret redacted".
    private var crumb: Text {
        var parts = [artifact.kind, ScopedSetting.bytes(artifact.size)]
        if artifact.redactions > 0 {
            parts.append("\(artifact.redactions) secret\(artifact.redactions == 1 ? "" : "s") redacted")
        }
        return Text(parts.joined(separator: " · ")).foregroundStyle(skin.color(skin.text.muted))
    }

    @ViewBuilder private var preview: some View {
        if let image = page.images[artifact.id] {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fit)
                .clipShape(RoundedRectangle(cornerRadius: skin.size.s6))
                .accessibilityLabel(artifact.name)
        } else if let text = page.texts[artifact.id] {
            if artifact.isMarkdown {
                AinkradCard {
                    AinkradMarkdownText(text: text).frame(maxWidth: .infinity, alignment: .leading)
                }
            } else {
                AinkradCodeBlock(text, language: artifact.ext.isEmpty ? nil : artifact.ext)
            }
        } else if artifact.isText || artifact.isImage {
            AinkradSkeletonRow(widthFraction: 0.9, showsAvatar: false)
        } else {
            AinkradEmptyState(
                icon: "arrow.down.doc", title: "No preview for \(artifact.mime)",
                message: "Download it to open it with the app you choose."
            )
            .frame(maxWidth: .infinity)
            .frame(height: skin.size.s200)
        }
    }

    private var provenance: some View {
        AinkradCard {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                TileHead(title: "Produced by")
                if let agent = model.agent(artifact.agentID) {
                    row("Agent") {
                        HStack(spacing: skin.size.s6) {
                            AgentFigure(agent: agent, model: model, size: skin.size.s18)
                            Text("\(agent.name) · \(agent.role)").citadelFont("t12")
                        }
                    }
                }
                if let run = artifact.runID {
                    row("Run") {
                        link(runText(run)) { store.open(.run(run)) }
                    }
                }
                if let issue = model.issue(artifact.issueID) {
                    row("Issue") {
                        Text(issue.key).citadelFont("t12", mono: true).foregroundStyle(theme.accentSecondary)
                    }
                }
                if let requirement = model.requirements.first(where: { $0.id == artifact.requirementID }) {
                    row("Requirement") {
                        link("\(requirement.key) \(requirement.title)") {
                            model.requirementsPage.selectedID = requirement.id
                            store.screen = .requirements
                        }
                    }
                }
                if let shown = shownIn { row("Shown in") { Text(shown).citadelFont("t12") } }
                row("Stored") {
                    Text("sha256 \(Self.shortHash(artifact.sha256)) · \(artifact.mime)").citadelFont("t11", mono: true)
                        .textSelection(.enabled)
                }
            }
        }
    }

    /// "R-12 thread · CIT-61".
    private var shownIn: String? {
        let requirement = model.requirements.first { $0.id == artifact.requirementID }.map { "\($0.key) thread" }
        let parts = [requirement, model.issue(artifact.issueID)?.key].compactMap { $0 }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    /// "#428 · 11:31–11:40".
    private func runText(_ id: Int64) -> String {
        guard let run = model.runs[id], let start = run.startedAt else { return "#\(id)" }
        let time = Date.FormatStyle.dateTime.hour().minute()
        return "#\(id) · \(start.formatted(time))\(run.endedAt.map { "–\($0.formatted(time))" } ?? "")"
    }

    static func shortHash(_ sha: String) -> String { sha.count > 8 ? "\(sha.prefix(4))…\(sha.suffix(2))" : sha }

    private func row(_ label: String, @ViewBuilder value: () -> some View) -> some View {
        HStack(spacing: skin.size.s8) {
            Text(label).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            Spacer(minLength: skin.size.s8)
            value().lineLimit(1)
        }
    }

    /// An accent mono value that opens its target; underlined on hover.
    private func link(_ text: String, action: @escaping () -> Void) -> some View {
        LinkText(text: text, action: action)
    }
}

private struct LinkText: View {
    let text: String
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        Text(text).citadelFont("t12", mono: true).foregroundStyle(theme.accentSecondary).underline(hovering)
            .onHover { hovering = $0 }
            .onTapGesture(perform: action)
            .accessibilityAddTraits(.isButton)
    }
}
