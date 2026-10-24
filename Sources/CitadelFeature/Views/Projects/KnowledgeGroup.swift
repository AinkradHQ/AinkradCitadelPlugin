import AinkradAppKit
import SwiftUI

/// The project's knowledge (API minor 16): every entry, whatever its status — Accept / Reject… on a proposal,
/// Retire… / Supersede… on an accepted one. A kind or status this build doesn't know is shown as its word.
struct KnowledgeGroup: View {
    let store: CitadelStore
    let model: CompanyModel
    let project: Int64
    @Environment(\.ainkradSkin) private var skin

    private var entries: [KnowledgeInfo]? { model.projectsPage.knowledge[project] }

    var body: some View {
        let proposed = entries?.filter { $0.status == "proposed" }.count ?? 0
        ProfileGroup(title: "Knowledge", note: proposed > 0 ? "\(proposed) proposed" : "what runs are given") {
            if entries?.isEmpty == true {
                Text("No knowledge yet.").citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
            }
            ForEach(entries ?? []) { entry in
                KnowledgeRow(store: store, model: model, project: project, entry: entry)
            }
        }
    }
}

private struct KnowledgeRow: View {
    let store: CitadelStore
    let model: CompanyModel
    let project: Int64
    let entry: KnowledgeInfo
    @State private var expanded = false
    @State private var rejecting = false
    @State private var retiring = false
    @State private var superseding = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s4) {
            HStack(spacing: skin.size.s8) {
                AinkradBadge(text: entry.kind)
                Text(entry.title).citadelFont("t12", weight: "semibold")
                    .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                AinkradBadge(text: entry.status, status: status)
                Spacer(minLength: skin.size.s8)
                actions
            }
            Text(meta).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(2)
            if expanded {
                Text(entry.body + (entry.bodyTruncated ? "\n… (cut at 16 KB)" : ""))
                    .citadelFont("t12", mono: true).foregroundStyle(skin.color(skin.text.primary))
                    .textSelection(.enabled).fixedSize(horizontal: false, vertical: true)
            }
            AinkradButton(title: expanded ? "Hide body" : "Show body", style: .ghost) { expanded.toggle() }
                .borderless().compact().fixedSize()
        }
        .padding(.vertical, skin.size.s4)
        .ainkradSheet(isPresented: $rejecting) {
            PromptSheet(
                title: "Reject \(entry.title)?", message: "It is never given to a run. The agent sees your reason.",
                placeholder: "Why not", confirmTitle: "Reject", isDestructive: true, text: "",
                isPresented: $rejecting
            ) { store.decide(entry, project: project, accept: false, reason: $0) }
        }
        .ainkradSheet(isPresented: $retiring) {
            PromptSheet(
                title: "Retire \(entry.title)?", message: "It is kept for history and no longer given to runs.",
                placeholder: "Why", confirmTitle: "Retire", isDestructive: true, text: "", isPresented: $retiring
            ) { store.retire(entry, project: project, reason: $0) }
        }
        .ainkradSheet(isPresented: $superseding) {
            SupersedeSheet(entry: entry, isPresented: $superseding) {
                store.supersede(entry, project: project, body: $0)
            }
        }
    }

    @ViewBuilder private var actions: some View {
        switch entry.status {
        case "proposed":
            AinkradButton(title: "Reject…", style: .ghost) { rejecting = true }.outlined().compact().fixedSize()
            AinkradButton(title: "Accept") { store.decide(entry, project: project, accept: true) }
                .compact().fixedSize()
        case "accepted":
            AinkradButton(title: "Supersede…", style: .ghost) { superseding = true }.outlined().compact().fixedSize()
            AinkradButton(title: "Retire…", style: .danger) { retiring = true }.outlined().compact().fixedSize()
        default: EmptyView()
        }
    }

    private var status: AinkradStatus {
        switch entry.status {
        case "accepted": .success
        case "proposed": .warning
        case "rejected": .danger
        default: .neutral
        }
    }

    /// "proposed by Mira · applies to profile.lint · superseded by #12 · CI failed twice".
    private var meta: String {
        var parts = [
            entry.proposedBy.map { "proposed by \(model.agent($0)?.name ?? "agent \($0)")" } ?? "added by you"
        ]
        if let target = entry.target { parts.append("applies to \(target)") }
        if let old = entry.supersedes { parts.append("supersedes #\(old)") }
        if let new = entry.supersededBy { parts.append("superseded by #\(new)") }
        if let why = entry.reason ?? entry.rationale { parts.append(why) }
        return parts.joined(separator: " · ")
    }
}

/// Supersede: the new version's body (the old one's to start from); the old entry is retired.
private struct SupersedeSheet: View {
    let entry: KnowledgeInfo
    @Binding var isPresented: Bool
    let confirm: (String) -> Void
    @State private var text = ""
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s12) {
            Text("Supersede \(entry.title)").citadelFont("t15", weight: "semibold")
            Text("The new version is accepted at once; this one is retired.").citadelFont("t12")
                .foregroundStyle(skin.color(skin.text.muted))
            AinkradTextArea(text: $text, placeholder: "The new version")
            HStack(spacing: skin.size.s8) {
                Spacer()
                AinkradButton(title: "Cancel", style: .ghost) { isPresented = false }.fixedSize()
                AinkradButton(title: "Supersede") {
                    confirm(text)
                    isPresented = false
                }
                .fixedSize().disabled(text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            }
        }
        .padding(skin.size.s20)
        .frame(width: skin.size.s440)
        .onAppear { text = entry.body }
    }
}
