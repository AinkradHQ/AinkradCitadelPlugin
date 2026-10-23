import AinkradAppKit
import SwiftUI

/// Screen 08: issues that stopped moving and the engine's reason — stuck (red, nothing moves them without you)
/// above slowing (amber), each with its reason, the engine's last repair, and the fixes the server can take. A
/// card leaves when the engine's next read says the issue moves again, not on click.
struct StuckView: View {
    let store: CitadelStore
    let model: CompanyModel
    @State private var project: Int64?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let lists = model.stuckList(project: project)
        VStack(alignment: .leading, spacing: 0) {
            PaneTitle(title: "Why stuck", crumb: crumb(lists)) { filters }
            ScrollView {
                VStack(alignment: .leading, spacing: skin.size.s12) {
                    if lists.stuck.isEmpty && lists.slowing.isEmpty {
                        AinkradEmptyState(
                            icon: "flag", title: "Nothing is stuck",
                            message: "Every issue has a next actor that can move it."
                        )
                        .frame(maxWidth: .infinity).padding(.top, skin.size.s60)
                    }
                    section("Stuck — no next actor can move these", lists.stuck)
                    section("Slowing — moving, but past their usual time", lists.slowing)
                }
                .padding(.horizontal, skin.size.s20)
                .padding(.bottom, skin.size.s20)
                .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: lists.stuck + lists.slowing)
            }
            .offlineDimmed()
        }
    }

    private func crumb(_ lists: (stuck: [StuckInfo], slowing: [StuckInfo])) -> Text {
        let muted = skin.color(skin.text.muted)
        return Text("Issues that stopped moving, and the engine's reason · ").foregroundStyle(muted)
            + Text("\(lists.stuck.count) stuck").foregroundStyle(status.danger)
            + Text(verbatim: " · ").foregroundStyle(muted)
            + Text("\(lists.slowing.count) slowing").foregroundStyle(status.warning)
    }

    private var filters: some View {
        HStack(spacing: skin.size.s6) {
            AinkradToggleButton(
                isOn: Binding(get: { project == nil }, set: { if $0 { project = nil } }), title: "All projects")
            ForEach(model.projects) { item in
                AinkradToggleButton(
                    isOn: Binding(get: { project == item.id }, set: { if $0 { project = item.id } }), title: item.key)
            }
        }
    }

    @ViewBuilder private func section(_ title: String, _ items: [StuckInfo]) -> some View {
        if !items.isEmpty {
            Text(skin.labelCased(title)).citadelFont("t10", weight: "semibold")
                .foregroundStyle(skin.color(skin.text.muted)).padding(.top, skin.size.s4)
            ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                StuckCard(store: store, model: model, stuck: item)
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
    }
}

/// One stuck issue: icon, key + title, the reason in one bold sentence and the detail plain, the engine's trail,
/// then the fixes — the engine's recommendation first.
private struct StuckCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let stuck: StuckInfo
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    private var issue: IssueInfo? { model.issue(stuck.issueID) }
    private var tone: AinkradChartTone { stuck.isSlowing ? .warning : .danger }

    var body: some View {
        AinkradCard {
            HStack(alignment: .top, spacing: skin.size.s14) {
                TypeGlyph(glyph: stuck.glyph, tone: tone, isLarge: true)
                VStack(alignment: .leading, spacing: skin.size.s6) {
                    (Text(issue.map { "\($0.key) " } ?? "").foregroundStyle(theme.accentSecondary)
                        .font(skin.font(AinkradFontToken(sizeKey: "t14", mono: "family")))
                        + Text(issue?.title ?? stuck.kind.replacingOccurrences(of: "_", with: " "))
                        .foregroundStyle(skin.color(skin.text.primary)))
                        .citadelFont("t14", weight: "semibold").lineLimit(1)
                    (Text(sentence(stuck.reason)).foregroundStyle(skin.color(skin.text.primary)).bold()
                        + Text(" \(sentence(stuck.action))").foregroundStyle(skin.color(skin.text.muted)))
                        .citadelFont("t12_5").fixedSize(horizontal: false, vertical: true)
                    if let trail {
                        Text(trail).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.faint))
                    }
                    fixes.padding(.top, skin.size.s4)
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .rimTint(tone)
    }

    /// "engine: rewake at 10:12 · next: reassign to lead".
    private var trail: String? {
        var parts: [String] = []
        if let last = stuck.lastRepair {
            let at = stuck.lastRepairAt.map { " at \($0.formatted(date: .omitted, time: .shortened))" } ?? ""
            parts.append("engine: \(last.replacingOccurrences(of: "_", with: " "))\(at)")
        }
        if let agent = model.agent(stuck.agentID) { parts.append("waits on \(agent.name)") }
        parts.append(stuck.kind.replacingOccurrences(of: "_", with: " "))
        return parts.joined(separator: " · ")
    }

    @ViewBuilder private var fixes: some View {
        let lead = model.lead(ofProject: issue?.projectID)
        HStack(spacing: skin.size.s8) {
            recommended(lead: lead)
            if stuck.issueID != nil {
                AinkradMenuButton(
                    items: model.agents.values.filter { $0.status == "active" }.sorted { $0.name < $1.name }.map {
                        agent in
                        AinkradMenuItem(title: "\(agent.name) · \(agent.role)", systemName: nil) {
                            store.reassign(stuck, to: agent.id)
                        }
                    }
                ) { Text("Reassign…") }
            }
            if let agent = stuck.agentID {
                AinkradButton(title: "Open \(model.agent(agent)?.name ?? "agent")", style: .ghost) {
                    store.open(.agent(agent))
                }
                .borderless().secondaryAccent().compact().fixedSize()
            }
            Text(why(lead: lead)).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
        }
    }

    /// The engine's recommendation as the primary fix, when the server takes it; otherwise disabled with why.
    @ViewBuilder private func recommended(lead: AgentInfo?) -> some View {
        switch stuck.repair {
        case "unblock" where stuck.issueID != nil:
            AinkradButton(title: "Unblock", style: .primary) { store.unblock(stuck) }.compact().fixedSize()
        case "reassign_to_lead", "escalate":
            if let lead, stuck.issueID != nil {
                AinkradButton(title: "Reassign to \(lead.name)", style: .primary) { store.reassign(stuck, to: lead.id) }
                    .compact().fixedSize()
            }
        case let repair?:
            // TODO(citadel#nudge): rewake / requeue / release_checkout need the server's nudge endpoint.
            AinkradButton(title: repair.replacingOccurrences(of: "_", with: " ").capitalized, style: .primary) {}
                .compact().fixedSize().disabled(true)
                .ainkradTooltip("The engine does this by itself; a manual nudge needs the server's nudge endpoint")
        case nil: EmptyView()
        }
    }

    private func why(lead: AgentInfo?) -> String {
        switch stuck.repair {
        case "reassign_to_lead", "escalate": lead.map { "the engine recommends \($0.name), the team lead" } ?? ""
        case "unblock": "its blockers are closed"
        case let repair?: "the engine will \(repair.replacingOccurrences(of: "_", with: " ")) on its own"
        case nil: ""
        }
    }

    private func sentence(_ text: String) -> String {
        guard let first = text.first else { return text }
        let capped = first.uppercased() + text.dropFirst()
        return capped.hasSuffix(".") ? capped : capped + "."
    }
}
