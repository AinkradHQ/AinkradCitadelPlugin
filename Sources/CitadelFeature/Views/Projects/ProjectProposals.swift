import AinkradAppKit
import SwiftUI

/// "Proposed by agents" (`.pj-props`): each proposal as a violet card — who, what, the diff, why — with Reject… /
/// Accept. Reject grows a reason box in place (it goes back to the agent). Nothing applies on its own (#48).
struct ProposalsTile: View {
    let store: CitadelStore
    let facts: ProjectFacts
    let history: () -> Void
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let proposals = facts.profile?.proposals ?? []
        let violet = skin.color(skin.palette.accentViolet)
        BentoTile {
            VStack(alignment: .leading, spacing: skin.size.s8) {
                OverviewHead(
                    title: "Proposed by agents", count: proposals.isEmpty ? nil : proposals.count, countTint: violet
                ) {
                    TileLink("History") {
                        store.loadProfileHistory(facts.project.id)
                        history()
                    }
                }
                if proposals.isEmpty {
                    zero
                } else {
                    ForEach(Array(proposals.enumerated()), id: \.element.id) { index, proposal in
                        ProposalCard(store: store, facts: facts, proposal: proposal, order: index)
                            .transition(.opacity.combined(with: .scale(scale: 0.96, anchor: .top)))
                    }
                }
            }
            .frame(maxHeight: .infinity, alignment: .top)
        }
        .animation(reduceMotion ? nil : skin.animation(skin.motion.present), value: proposals.map(\.id))
    }

    private var zero: some View {
        VStack(spacing: skin.size.s4) {
            Text("✓").citadelFont("t14", weight: "bold").foregroundStyle(skin.color(skin.palette.success))
                .frame(width: skin.size.s36, height: skin.size.s36)
                .background(
                    skin.color(skin.palette.success).opacity(skin.opacity.o14),
                    in: RoundedRectangle(cornerRadius: skin.size.s11))
            Text("Nothing to review").citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
            Text("Agents' suggested edits to this project land here and never apply on their own.").citadelFont("t11")
                .foregroundStyle(skin.color(skin.text.faint)).multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, skin.size.s20)
    }
}

private struct ProposalCard: View {
    let store: CitadelStore
    let facts: ProjectFacts
    let proposal: ProposalInfo
    let order: Int
    @State private var rejecting = false
    @State private var reason = ""
    @State private var shown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let violet = skin.color(skin.palette.accentViolet)
        let agent = facts.model.agent(proposal.agentID)
        let diff = (facts.profile ?? ProfileInfo()).diff(proposal)
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        VStack(alignment: .leading, spacing: skin.size.s8) {
            HStack(spacing: skin.size.s10) {
                if let agent { AgentFigure(agent: agent, model: facts.model, size: skin.size.s26) }
                VStack(alignment: .leading, spacing: 0) {
                    Text(agent?.name ?? "An agent").citadelFont("t12_5", weight: "bold").foregroundStyle(
                        skin.color(skin.text.primary))
                    Text(proposal.title).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
                }
            }
            VStack(alignment: .leading, spacing: skin.size.s2) {
                if let old = diff.old {
                    Text("− \(old)").foregroundStyle(skin.color(skin.palette.danger))
                }
                Text(diff.old == nil ? diff.new : "+ \(diff.new)").foregroundStyle(skin.color(skin.palette.success))
            }
            .citadelFont("t11", mono: true)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, skin.size.s10).padding(.vertical, skin.size.s8)
            .background(
                skin.color(.palette("black", skin.opacity.o28)), in: RoundedRectangle(cornerRadius: skin.size.s9))
            if let why = proposal.rationale {
                Text(why).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).fixedSize(
                    horizontal: false, vertical: true)
            }
            if rejecting {
                VStack(alignment: .trailing, spacing: skin.size.s8) {
                    AinkradTextArea(
                        text: $reason,
                        placeholder:
                            "Why not? — goes back to \(agent?.name ?? "the agent") so it doesn't propose this again",
                        minHeight: skin.size.s56)
                    HStack(spacing: skin.size.s6) {
                        AinkradButton(title: "Cancel", style: .secondary) { rejecting = false }.compact().fixedSize()
                        AinkradButton(title: "Reject", style: .danger) {
                            store.decide(proposal, project: facts.project.id, accept: false, reason: reason)
                            store.toast(
                                AinkradRichToast(
                                    title: "Proposal rejected",
                                    body:
                                        "\(agent?.name ?? "The agent") was told\(reason.isEmpty ? "" : ": “\(reason)”")"
                                ))
                        }
                        .compact().fixedSize()
                    }
                }
                .transition(.opacity.combined(with: .move(edge: .top)))
            } else {
                HStack(spacing: skin.size.s6) {
                    Spacer()
                    AinkradButton(title: "Reject…", style: .secondary) { rejecting = true }.compact().fixedSize()
                    AinkradButton(title: "Accept", style: .primary) {
                        store.decide(proposal, project: facts.project.id, accept: true)
                        store.toast(
                            AinkradRichToast(
                                title: "Profile updated",
                                body: "\(agent?.name ?? "The agent")'s change applies from the next run.",
                                status: .success))
                    }
                    .compact().fixedSize()
                }
            }
        }
        .padding(skin.size.s12)
        .background(violet.opacity(skin.opacity.o07), in: shape)
        .overlay(shape.strokeBorder(violet.opacity(skin.opacity.o25)))
        .opacity(shown || reduceMotion ? 1 : 0)
        .offset(y: shown || reduceMotion ? 0 : skin.size.s8)
        .animation(
            reduceMotion ? nil : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.25)),
            value: rejecting
        )
        .onAppear {
            withAnimation(
                skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.35)).delay(Double(order) * 0.06)
            ) {
                shown = true
            }
        }
    }
}
