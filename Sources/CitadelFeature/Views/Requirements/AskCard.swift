import AinkradAppKit
import SwiftUI

/// An agent's open question (`.tl-ask`): amber gradient card — "Kestrel asks you", role · on KEY · context, age,
/// the question, quick replies (the first primary), and the route line. Answering wakes the asker, not the CEO.
struct AskCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let question: QuestionInfo
    let requirement: Int64
    @State private var shown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let asker = model.agent(question.agentID)
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        let run = question.runID.flatMap { model.runs[$0] }
        let context = run.map { $0.isLive ? "its run waits on you" : "while planning" }
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(spacing: skin.size.s12) {
                if let asker { AgentFigure(agent: asker, model: model, size: skin.size.s30) }
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    Text("\(asker?.name ?? "An agent") asks you").citadelFont("t13", weight: "semibold")
                        .foregroundStyle(status.warning)
                    (Text(
                        [asker?.roleLabel, "on "].compactMap { $0 }.joined(separator: " · "))
                        + Text(question.issueKey).foregroundStyle(theme.accentSecondary)
                        + Text(context.map { " · \($0)" } ?? ""))
                        .citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
                }
                Spacer(minLength: skin.size.s8)
                Text(Fmt.age(Date().timeIntervalSince(question.askedAt))).citadelFont("t11", mono: true)
                    .foregroundStyle(skin.color(skin.text.faint))
            }
            richText(question.text).citadelFont("t14").lineSpacing(skin.size.s4)
                .foregroundStyle(skin.color(skin.text.primary)).fixedSize(horizontal: false, vertical: true)
            if !question.options.isEmpty {
                QuickReplies(options: question.options) {
                    store.answer($0, question: question, requirement: requirement)
                }
            }
            Text("↪ Your answer goes to \(asker?.name ?? "the agent") and wakes it — not to the \(owner)")
                .citadelFont("t11").foregroundStyle(status.warning.opacity(skin.opacity.o80))
        }
        .padding(.horizontal, skin.size.s16)
        .padding(.vertical, skin.size.s14)
        .background(
            shape.fill(
                LinearGradient(
                    colors: [status.warning.opacity(skin.opacity.o12), status.warning.opacity(skin.opacity.o03)],
                    startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(shape.strokeBorder(status.warning.opacity(skin.opacity.o50), lineWidth: 1))
        .shadow(color: status.warning.opacity(skin.opacity.o08), radius: skin.size.s15, y: skin.size.s10)
        .scaleEffect(shown || reduceMotion ? 1 : 0.98)
        .offset(y: shown || reduceMotion ? 0 : skin.size.s8)
        .opacity(shown ? 1 : 0)
        .onAppear {
            withAnimation(
                reduceMotion
                    ? nil : skin.animation(AinkradAnimationToken(curve: "spring", response: 0.5, damping: 0.75))
            ) {
                shown = true
            }
        }
    }

    private var owner: String {
        model.ownerWord(model.requirements.first { $0.id == requirement }?.ownerAgentID)
    }
}

/// Artifacts an agent published (`.tl-arts`): tiles in a fill grid — a thumbnail or a doc tile, the name and
/// "kind · size". A tile opens its preview in the requirement drawer.
struct ArtifactTiles: View {
    let store: CitadelStore
    let model: CompanyModel
    let artifacts: [ArtifactInfo]
    /// Tapping opens the drawer's preview (requirement thread) or screen 13 (agent threads).
    var open: ((ArtifactInfo) -> Void)?
    /// One per row (the threads rail's Files card).
    var singleColumn = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let columns =
            singleColumn
            ? [GridItem(.flexible())] : [GridItem(.adaptive(minimum: skin.size.s220), spacing: skin.size.s8)]
        LazyVGrid(columns: columns, alignment: .leading, spacing: skin.size.s8) {
            ForEach(artifacts) { artifact in
                ArtifactTile(model: model, artifact: artifact) {
                    if let open {
                        open(artifact)
                    } else {
                        model.requirementsPage.drawer.append(.artifact(artifact.id))
                    }
                }
                .onAppear { store.loadPreview(artifact) }
            }
        }
    }
}

struct ArtifactTile: View {
    let model: CompanyModel
    let artifact: ArtifactInfo
    let open: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        AinkradTapArea(help: artifact.name, action: open) {
            HStack(spacing: skin.size.s10) {
                ArtifactThumb(model: model, artifact: artifact)
                VStack(alignment: .leading, spacing: skin.size.s1) {
                    Text(artifact.name).citadelFont("t12", weight: "medium").lineLimit(1).truncationMode(.middle)
                        .foregroundStyle(skin.color(skin.text.primary))
                    Text(model.artifactMeta(artifact)).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
                        .lineLimit(1)
                }
                Spacer(minLength: 0)
            }
            .padding(skin.size.s8)
            .background(shape.fill(skin.color(.palette("foreground", hovering ? skin.opacity.o07 : skin.opacity.o05))))
            .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
            .contentShape(shape)
        }
        .offset(y: hovering && !reduceMotion ? -skin.size.s2 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// A 60 × 40 image thumbnail, or a 40 pt blue doc tile.
struct ArtifactThumb: View {
    let model: CompanyModel
    let artifact: ArtifactInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        if let image = model.artifactsPage.images[artifact.id] {
            Image(nsImage: image).resizable().aspectRatio(contentMode: .fill)
                .frame(width: skin.size.s60, height: skin.size.s40)
                .clipShape(RoundedRectangle(cornerRadius: skin.size.s7, style: .continuous))
        } else {
            Image(systemName: artifact.isImage ? "photo" : "doc.text").citadelFont("t16")
                .foregroundStyle(skin.color(skin.palette.accentPrimary))
                .frame(width: skin.size.s40, height: skin.size.s40)
                .background(
                    skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o14),
                    in: RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous))
        }
    }
}

extension CompanyModel {
    /// "report · 2.1 KB", "screenshot · 1440×900" — a tile's meta. The full preview's head also carries the
    /// image's bytes ("screenshot · 412 KB · 1440×900"), as the prototype's `pv-arthead` does.
    func artifactMeta(_ artifact: ArtifactInfo, sized: Bool = false) -> String {
        if artifact.isImage, let size = artifactsPage.images[artifact.id]?.size {
            let bytes = sized ? [ScopedSetting.bytes(artifact.size)] : []
            return ([artifact.kind] + bytes + ["\(Int(size.width))×\(Int(size.height))"])
                .joined(separator: " · ")
        }
        return "\(artifact.kind) · \(ScopedSetting.bytes(artifact.size))"
    }
}
