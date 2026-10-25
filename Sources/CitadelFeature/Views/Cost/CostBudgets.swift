import AinkradAppKit
import SwiftUI

/// `budgetsTile`: every budget as a ring card — spent / cap (the cap pill edits inline), warn % with where it
/// comes from (↺ resets an override), the state; a stopped budget links to its raise approval. Caps in tokens.
struct BudgetsCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let add: () -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        BentoTile(padding: skin.size.s14) {
            VStack(alignment: .leading, spacing: skin.size.s10) {
                HStack(alignment: .firstTextBaseline, spacing: skin.size.s10) {
                    Text("Budgets").citadelFont("t13", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
                    Text("hard stop at the cap blocks new runs until you approve · warn % inherited unless set")
                        .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
                }
                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: skin.size.s250), spacing: skin.size.s10, alignment: .top)],
                    alignment: .leading, spacing: skin.size.s10
                ) {
                    ForEach(model.budgets) { budget in
                        BudgetCard(store: store, model: model, budget: budget)
                    }
                    NewBudgetTile(add: add)
                }
            }
        }
    }
}

private struct BudgetCard: View {
    let store: CitadelStore
    let model: CompanyModel
    let budget: BudgetInfo
    @Environment(\.ainkradSkin) private var skin

    private var inherited: Int { Int(model.limits["budget.warn_percent"]?.value ?? 80) }

    var body: some View {
        let percent = Int((budget.fraction * 100).rounded())
        let stopped = budget.fraction >= 1
        let pastWarn = budget.fraction >= budget.warnFraction
        let tint =
            stopped
            ? skin.color(skin.palette.danger)
            : pastWarn ? skin.color(skin.palette.warning) : skin.color(skin.palette.success)
        let scope = model.warnScope(budget)
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        HStack(spacing: skin.size.s14) {
            AinkradRingGauge(value: budget.fraction, tint: tint, diameter: skin.size.s56, lineWidth: skin.size.s6) {
                Text("\(percent)%").citadelFont("t11", weight: "bold", mono: true).foregroundStyle(
                    skin.color(skin.text.primary))
            }
            VStack(alignment: .leading, spacing: skin.size.s4) {
                Text(title).citadelFont("t12_5", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                    .lineLimit(1)
                HStack(spacing: skin.size.s4) {
                    Text("\(Fmt.tokens(budget.spent)) /").citadelFont("t12", mono: true).foregroundStyle(
                        skin.color(skin.text.muted))
                    InlineValuePill(text: Fmt.tokens(budget.cap), help: "Edit cap (tokens)") {
                        store.editBudgetCap(budget, text: $0, inheritsWarn: !isOverridden(scope))
                    }
                }
                HStack(spacing: skin.size.s6) {
                    Text("warn").citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                    InlineValuePill(text: "\(budget.warnPercent)%", help: "Edit warn %") {
                        store.editBudgetWarn(budget, text: $0, inherited: inherited)
                    }
                    chip(scope)
                }
                if stopped {
                    AinkradTapArea(
                        help: "New runs blocked — open the raise approval", action: { store.openBudgetApproval(budget) }
                    ) {
                        Text("stopped · new runs blocked ›").underline().citadelFont("t10_5", weight: "semibold")
                            .foregroundStyle(tint)
                    }
                } else {
                    Text(pastWarn ? "past warn" : "on track").citadelFont("t10_5", weight: "semibold").foregroundStyle(
                        tint)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(skin.size.s14)
        .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o03))))
        .overlay(shape.strokeBorder(tint.opacity(skin.opacity.o22), lineWidth: 1))
        .ainkradHoverLift(nil, cornerRadius: skin.size.s16)
        .ainkradContextMenu([
            AinkradMenuItem(title: "Delete budget", systemName: "trash", isDestructive: true) {
                store.deleteBudget(budget)
            }
        ])
    }

    /// "Company · October", "Sprint CIT S4", "Kestrel · week".
    private var title: String {
        if budget.scope.hasPrefix("sprint:") { return budget.label }
        if budget.period == "month" { return "\(budget.label) · \(Date().formatted(.dateTime.month(.wide)))" }
        return "\(budget.label) · \(budget.period)"
    }

    private func isOverridden(_ scope: AinkradValueScope) -> Bool {
        if case .overridden = scope { return true }
        return false
    }

    @ViewBuilder private func chip(_ scope: AinkradValueScope) -> some View {
        switch scope {
        case .inherited(let from): ScopeChip(text: from)
        case .overridden(let at, let inheritedValue):
            // ↺ only when the server actually has a company value to go back to — never a made-up default.
            if inheritedValue != nil {
                ScopeChip(text: at, overridden: true) {
                    store.editBudgetWarn(budget, text: nil, inherited: inherited)
                }
            } else {
                ScopeChip(text: at, overridden: true)
            }
        @unknown default: EmptyView()
        }
    }
}

/// The dashed "＋ New budget" card.
private struct NewBudgetTile: View {
    let add: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s16, style: .continuous)
        AinkradTapArea(action: add) {
            VStack(spacing: skin.size.s4) {
                Text("＋").citadelFont("t21")
                Text("New budget").citadelFont("t12")
            }
            .foregroundStyle(hovering ? skin.color(skin.text.primary) : skin.color(skin.text.faint))
            .frame(maxWidth: .infinity, minHeight: skin.size.s90)
            .overlay(
                shape.strokeBorder(
                    hovering
                        ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o45)
                        : skin.color(.palette("foreground", skin.opacity.o12)),
                    style: StrokeStyle(lineWidth: skin.size.s1_5, dash: [skin.size.s6, skin.size.s5]))
            )
            .contentShape(shape)
        }
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}
