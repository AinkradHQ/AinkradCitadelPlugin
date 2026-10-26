import AinkradAppKit
import SwiftUI

/// How a requirement reads on screen 12: its state word and colour (`REQ_STATE`), the ring's value and label, and
/// its project's colour pair (`projCol`).
@MainActor
enum RequirementLook {
    static func label(_ state: String) -> String {
        switch state {
        case "done": "Done"
        case "plan_review": "Plan to approve"
        case "planning": "Drafting"
        case "cancelled": "Cancelled"
        default: "In progress"
        }
    }

    static func tint(_ state: String, skin: AinkradSkin) -> Color {
        switch state {
        case "done": skin.color(skin.palette.success)
        case "plan_review": skin.color(skin.palette.warning)
        case "planning": skin.color(skin.palette.accentViolet)
        case "cancelled": skin.color(skin.text.faint)
        default: skin.color(skin.palette.accentSecondary)
        }
    }

    /// The ring: full with ✓ when done, an empty track with … while drafting, else % by points.
    static func ring(_ requirement: RequirementInfo) -> (value: Double?, label: String) {
        switch requirement.state {
        case "done": return (1, "✓")
        case "planning": return (nil, "…")
        default:
            let pct = requirement.points == 0 ? 0 : requirement.donePoints * 100 / requirement.points
            return (Double(pct) / 100, "\(pct)%")
        }
    }

    /// A project's two hero colours: the stored ones (API minor 18), else by its place in the company's list.
    static func colors(project: Int64?, model: CompanyModel) -> (Color, Color) {
        if let stored = ProjectIdentity.pair(model.projects.first { $0.id == project }?.color) { return stored }
        let palettes: [AinkradFigurePalette] = [.neonTide, .ultraviolet, .ember, .aurora, .orchid]
        let index = model.projects.sorted { $0.id < $1.id }.firstIndex { $0.id == project } ?? 0
        let palette = palettes[index % palettes.count]
        return (palette.lightColor, palette.deepColor)
    }
}

extension CompanyModel {
    /// The requirement's project: its plan's first epic's, else its issues'.
    func project(of requirement: RequirementInfo) -> ProjectInfo? {
        let id =
            requirementsPage.plans[requirement.id]?.epics.first?.projectID
            ?? issues.values.first { $0.requirementID == requirement.id }?.projectID
        return projects.first { $0.id == id }
    }
}

/// A requirement in the list (`.rqc`): a 42 pt ring in the state colour, the key with the glowing "N asks you"
/// badge and the age, the title, and "state · owner · done/pts". Hover nudges it right; the selection is tinted
/// with a left accent bar.
struct RequirementCard: View {
    let requirement: RequirementInfo
    let model: CompanyModel
    let isSelected: Bool
    /// Arrived while the list was open: an amber ring for a moment (`.arrive`).
    var isFresh = false
    let index: Int
    let open: () -> Void
    @State private var hovering = false
    @State private var shown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let tint = RequirementLook.tint(requirement.state, skin: skin)
        let ring = RequirementLook.ring(requirement)
        let asks = model.waitingCount(requirement)
        let owner = model.agent(requirement.ownerAgentID) ?? model.ceo
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        AinkradTapArea(action: open) {
            HStack(spacing: skin.size.s12) {
                AinkradRingGauge(value: ring.value, tint: tint, diameter: skin.size.s42, lineWidth: skin.size.s4) {
                    Text(ring.label).citadelFont("t11", weight: "semibold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary))
                }
                VStack(alignment: .leading, spacing: skin.size.s3) {
                    HStack(spacing: skin.size.s6) {
                        Text(requirement.key).citadelFont("t10_5", mono: true).foregroundStyle(theme.accentSecondary)
                        if asks > 0, requirement.state != "done" { AsksBadge(count: asks) }
                        Spacer(minLength: skin.size.s4)
                        if let age = model.requirementAge(requirement) {
                            Text(age).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
                        }
                    }
                    Text(requirement.title).citadelFont("t13", weight: "semibold").lineLimit(1)
                        .foregroundStyle(skin.color(skin.text.primary))
                    HStack(spacing: skin.size.s6) {
                        Text(RequirementLook.label(requirement.state)).citadelFont("t11", weight: "medium")
                            .foregroundStyle(tint)
                        if let owner {
                            AgentFigure(agent: owner, model: model, size: skin.size.s16)
                            Text(owner.name).lineLimit(1)
                        }
                        if requirement.points > 0 {
                            Spacer(minLength: skin.size.s4)
                            Text(verbatim: "\(requirement.donePoints)/\(requirement.points) pts").citadelFont(
                                "t11", mono: true)
                        }
                    }
                    .citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.faint))
                }
            }
            .padding(skin.size.s12)
            .background(
                shape.fill(
                    isFresh
                        ? status.warning.opacity(skin.opacity.o14)
                        : isSelected
                            ? tint.opacity(skin.opacity.o10)
                            : skin.color(.palette("foreground", hovering ? skin.opacity.o06 : skin.opacity.o03)))
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    Rectangle().fill(tint).frame(width: skin.size.s3)
                }
            }
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    isFresh
                        ? status.warning
                        : isSelected
                            ? tint.opacity(skin.opacity.o45) : skin.color(.palette("foreground", skin.opacity.o06)),
                    lineWidth: 1)
            )
            .shadow(color: status.warning.opacity(isFresh ? skin.opacity.o45 : 0), radius: skin.size.s10)
            .contentShape(shape)
        }
        .opacity((requirement.state == "done" ? skin.opacity.o62 : 1) * (shown ? 1 : 0))
        .offset(x: hovering && !reduceMotion ? skin.size.s2 : 0, y: shown || reduceMotion ? 0 : skin.size.s8)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        // `arrive 1.6s ease-out`: amber ring, glow and tint fading back to the card.
        .animation(
            reduceMotion ? nil : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 1.6)), value: isFresh
        )
        .onAppear {
            guard !shown else { return }
            // `rise .35s` with a 40 ms stagger per card.
            withAnimation(
                reduceMotion
                    ? nil
                    : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.35)).delay(
                        Double(index) * 0.04)
            ) { shown = true }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isSelected] : [])
    }
}

/// The amber "1 asks you" badge with its slow glow (`askGlow 2.4s`).
struct AsksBadge: View {
    let count: Int
    var text: String?
    @State private var glow = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Text(text ?? "\(count) asks you").citadelFont("t10", weight: "semibold")
            .foregroundStyle(skin.color(skin.palette.background))
            .padding(.horizontal, skin.size.s6)
            .padding(.vertical, skin.size.s1)
            .background(status.warning, in: RoundedRectangle(cornerRadius: skin.size.s5))
            .shadow(color: status.warning.opacity(glow ? skin.opacity.o60 : 0), radius: skin.size.s5)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(
                    skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 1.2)).repeatForever(
                        autoreverses: true)
                ) { glow = true }
            }
    }
}
