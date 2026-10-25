import AinkradAppKit
import SwiftUI

/// One inbox card (`.apc`): the type's icon tile with the asker's orb on its corner, the type label in its colour
/// with "● run paused" when it holds a live run, the title and the line under it. Selected: tinted with a left
/// accent bar; hover nudges right; cards rise in one after another.
struct ApprovalCard: View {
    let model: CompanyModel
    let approval: ApprovalInfo
    let isSelected: Bool
    let answered: Bool
    let index: Int
    let onTap: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var kind: ApprovalFilter { ApprovalFilter.of(approval) }
    private var rejected: Bool { approval.status != "approved" }

    private var tint: Color {
        guard answered else { return kind.tint(skin) }
        return rejected ? skin.color(skin.palette.warning) : skin.color(skin.palette.success)
    }

    var body: some View {
        let summary = model.summary(approval)
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        AinkradTapArea(action: onTap) {
            HStack(alignment: .top, spacing: skin.size.s11) {
                icon
                VStack(alignment: .leading, spacing: skin.size.s3) {
                    HStack(spacing: skin.size.s6) {
                        Text(kind == .all ? summary.typeLabel : Self.label(approval).uppercased())
                            .citadelFont("t10_5", weight: "semibold").tracking(skin.size.s1 / 3)
                            .foregroundStyle(tint)
                        Spacer(minLength: 0)
                        if !answered, model.holdsRun(approval) { RunPaused() }
                    }
                    Text(summary.title).citadelFont("t12_5", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
                    Text(subtitle(summary)).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                        .lineLimit(1)
                }
            }
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s11)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(shape.fill(fill))
            .overlay(
                shape.strokeBorder(
                    isSelected ? tint.opacity(skin.opacity.o40) : skin.color(.palette("foreground", skin.opacity.o06)),
                    lineWidth: 1)
            )
            .overlay(alignment: .leading) {
                if isSelected {
                    UnevenRoundedRectangle(
                        topLeadingRadius: skin.size.s14, bottomLeadingRadius: skin.size.s14, style: .continuous
                    )
                    .fill(tint).frame(width: skin.size.s3)
                }
            }
            .contentShape(shape)
        }
        .opacity(answered ? skin.opacity.o55 : 1)
        .offset(x: hovering && !reduceMotion ? skin.size.s2 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
        .riseIn(delay: Double(index) * 0.04)
    }

    private var fill: Color {
        if isSelected { return tint.opacity(skin.opacity.o09) }
        return skin.color(.palette("foreground", hovering ? skin.opacity.o06 : skin.opacity.o03))
    }

    private var icon: some View {
        ZStack(alignment: .bottomTrailing) {
            Group {
                if answered {
                    Text(rejected ? "✕" : "✓").citadelFont("t14", weight: "bold")
                } else {
                    Image(systemName: kind.systemImage).citadelFont("t16", weight: "medium")
                }
            }
            .foregroundStyle(tint)
            .frame(width: skin.size.s38, height: skin.size.s38)
            .background(tint.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s11))
            if let asker = model.agent(approval.requestedBy) {
                AgentFigure(agent: asker, model: model, size: skin.size.s18)
                    .background(Circle().fill(skin.color(.palette("background", 1))).padding(-skin.size.s2))
                    .offset(x: skin.size.s6, y: skin.size.s6)
            }
        }
    }

    private func subtitle(_ summary: ApprovalSummary) -> String {
        guard answered else {
            return approval.kind == "permission_escalation"
                ? "permission escalation · run is waiting" : summary.subtitle
        }
        return [approval.status == "approved" ? "approved by you" : "\(approval.status) by you", approval.reply]
            .compactMap { $0 }.joined(separator: " · ")
    }

    /// The card's type label: "Sprint commit", "PR merge", "Budget overrun", "Hire", "Permission".
    static func label(_ approval: ApprovalInfo) -> String {
        switch approval.kind {
        case "sprint_commit": "Sprint commit"
        case "plan_approval": "Plan approval"
        case "pr_merge": "PR merge"
        case "workflow_push": "Workflow push"
        case "budget_overrun": "Budget overrun"
        case "hire_agent": "Hire"
        case "permission_escalation": "Permission"
        default: approval.kind.replacingOccurrences(of: "_", with: " ").capitalized
        }
    }
}

/// "● run paused": a pulsing amber dot with its glow, then the words.
struct RunPaused: View {
    @State private var dim = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let amber = skin.color(skin.palette.warning)
        HStack(spacing: skin.size.s4) {
            Circle().fill(amber).frame(width: skin.size.s6, height: skin.size.s6)
                .shadow(color: amber, radius: skin.size.s4)
                .opacity(dim ? skin.opacity.o35 : 1)
            Text("run paused").citadelFont("t10_5")
        }
        .foregroundStyle(amber)
        .onAppear {
            guard !reduceMotion else { return }
            withAnimation(skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 0.7)).repeatForever()) {
                dim = true
            }
        }
    }
}

/// The type's glyph on a tinted rounded square (the mockup's `.ty`).
struct TypeGlyph: View {
    let glyph: String
    let tone: AinkradChartTone
    /// The detail head's larger square.
    var isLarge = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let color = tone.tint(skin)
        let size = isLarge ? skin.size.s36 : skin.size.s28
        Text(glyph).citadelFont(isLarge ? "t16" : "t13", weight: "semibold")
            .foregroundStyle(color)
            .frame(width: size, height: size)
            .background(color.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s8))
            .accessibilityHidden(true)
    }
}
