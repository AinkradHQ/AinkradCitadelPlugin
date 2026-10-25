import AinkradAppKit
import SwiftUI

/// The stage's hero (`.ap-hero`): the type's 64 pt icon tile, "Type · crumb", the title, the state pill and the
/// kind's chips, and the involved agents' orbs overlapping on the right — on a gradient of the type's colour.
struct ApprovalHero: View {
    let tint: Color
    let systemImage: String
    let crumb: String
    let title: String
    let state: HeroState
    let chips: [HeroChip]
    let agents: [AgentInfo]
    let model: CompanyModel
    @State private var popped = false
    /// The icon tile pops in just after the hero rises (`tstPop .5s .1s`).
    private static let popDelay = 0.1
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s20, style: .continuous)
        HStack(alignment: .center, spacing: skin.size.s16) {
            Image(systemName: systemImage).citadelFont("t24", weight: "medium").foregroundStyle(tint)
                .frame(width: skin.size.s64, height: skin.size.s64)
                .background(tint.opacity(skin.opacity.o18), in: RoundedRectangle(cornerRadius: skin.size.s18))
                .overlay(RoundedRectangle(cornerRadius: skin.size.s18).strokeBorder(tint.opacity(skin.opacity.o30)))
                .scaleEffect(popped || reduceMotion ? 1 : 0.6)
            VStack(alignment: .leading, spacing: skin.size.s4) {
                Text(crumb).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                Text(title).citadelFont("t18", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(1)
                AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
                    state
                    ForEach(Array(chips.enumerated()), id: \.offset) { _, chip in chip }
                }
                .padding(.top, skin.size.s2)
            }
            Spacer(minLength: skin.size.s8)
            HStack(spacing: -skin.size.s14) {
                ForEach(agents) { agent in
                    AgentFigure(agent: agent, model: model, size: skin.size.s48)
                        .background(Circle().fill(skin.color(.palette("background", skin.opacity.o90))))
                }
            }
        }
        .padding(.horizontal, skin.size.s18)
        .padding(.vertical, skin.size.s16)
        .background(
            shape.fill(
                LinearGradient(
                    stops: [
                        .init(color: tint.opacity(skin.opacity.o16), location: 0),
                        .init(color: skin.color(.palette("background", skin.opacity.o50)), location: 0.65),
                    ], startPoint: .topLeading, endPoint: .bottomTrailing))
        )
        .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o30), lineWidth: 1))
        .riseIn()
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(
                skin.animation(AinkradAnimationToken(curve: "spring", response: 0.5, damping: 0.55)).delay(
                    Self.popDelay)
            ) { popped = true }
        }
    }
}

/// The hero's state pill (`.rq-st`): a glowing dot and "waiting on you" / "approved by you" in the state colour.
struct HeroState: View {
    let text: String
    let tint: Color
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s6) {
            Circle().fill(tint).frame(width: skin.size.s7, height: skin.size.s7).shadow(
                color: tint, radius: skin.size.s4)
            Text(text).citadelFont("t11", weight: "semibold")
        }
        .foregroundStyle(tint)
        .padding(.horizontal, skin.size.s10)
        .frame(height: skin.size.s24)
        .background(tint.opacity(skin.opacity.o14), in: RoundedRectangle(cornerRadius: skin.size.s7))
    }
}

/// A hero chip (`.chip`): an optional 16 pt orb, an optional mono key, the text.
struct HeroChip: View {
    var agent: AgentInfo?
    var key: String?
    var text: String = ""
    var mono = false
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s5) {
            if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s16) }
            if let key {
                Text(key).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.palette.accentSecondary))
            }
            if !text.isEmpty {
                Text(text).citadelFont("t11", mono: mono).foregroundStyle(skin.color(skin.text.primary))
            }
        }
        .padding(.horizontal, skin.size.s8)
        .frame(height: skin.size.s24)
        .background(
            skin.color(.palette("foreground", skin.opacity.o07)), in: RoundedRectangle(cornerRadius: skin.size.s7))
    }
}

/// A quoted note with its author (`.ap-quote`): orb, "Name · Role", the text.
struct QuoteCard: View {
    let agent: AgentInfo?
    let text: String
    var role: String?
    let model: CompanyModel
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(alignment: .top, spacing: skin.size.s10) {
            if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s30) }
            VStack(alignment: .leading, spacing: skin.size.s1) {
                if let agent {
                    Text("\(agent.name) · \(role ?? agent.role.capitalizedFirst)").citadelFont(
                        "t12", weight: "semibold"
                    )
                    .foregroundStyle(skin.color(skin.text.primary))
                }
                Text(text).citadelFont("t12_5").foregroundStyle(skin.color(skin.text.muted))
                    .lineSpacing(skin.size.s3).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.vertical, skin.size.s12)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)), in: RoundedRectangle(cornerRadius: skin.size.s14))
    }
}

/// A body card (`.rsd-card`): a header line (bold title, faint trailing note) over its content.
struct StageCard<Content: View>: View {
    let title: String
    var note: String?
    @ViewBuilder let content: Content
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s10) {
            HStack(spacing: skin.size.s8) {
                Text(title).citadelFont("t12_5", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                Spacer(minLength: skin.size.s8)
                if let note { Text(note).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)) }
            }
            content
        }
        .padding(.horizontal, skin.size.s14)
        .padding(.vertical, skin.size.s12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            skin.color(.palette("foreground", skin.opacity.o03)), in: RoundedRectangle(cornerRadius: skin.size.s16))
    }
}
