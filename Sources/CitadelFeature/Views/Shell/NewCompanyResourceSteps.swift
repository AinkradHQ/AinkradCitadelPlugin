import AinkradAppKit
import SwiftUI

/// Steps 5 to 7 of the New company wizard: the CEO's look, the company's budget and resources, the review.
struct NewCompanyResourceSteps: View {
    let store: CitadelStore
    @Binding var draft: NewCompanyDraft
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        switch draft.step {
        case 4: look
        case 5: resources
        default: review
        }
    }

    // MARK: - 4 CEO look

    @ViewBuilder private var look: some View {
        let palette = AinkradFigurePalette.named(draft.palette) ?? .neonTide
        NewCompanyHead(
            title: "How the CEO looks",
            line: "Its colour everywhere it appears. The figure animates by state, so you can read it at a glance.")
        field("Colour · \(palette.name)") { PaletteGrid(selection: $draft.palette) }
        field("In every state") {
            AinkradCardGrid(columns: 4, spacing: skin.size.s10) {
                ForEach(
                    [
                        (AinkradFigureState.idle, "Idle"), (.thinking, "Planning"), (.working, "Working"),
                        (.confused, "Needs you"),
                    ], id: \.1
                ) { state, label in
                    VStack(spacing: skin.size.s8) {
                        AinkradAgentFigure(
                            name: draft.ceoName, state: state, palette: palette,
                            harness: AgentLook.harness(draft.harness), size: skin.size.s64, isActive: true)
                        Text(label).citadelFont("t12", weight: "medium").foregroundStyle(skin.color(skin.text.muted))
                    }
                    .padding(.top, skin.size.s14).padding(.bottom, skin.size.s12)
                    .frame(maxWidth: .infinity)
                    .background(
                        skin.color(.palette("foreground", skin.opacity.o05)),
                        in: RoundedRectangle(cornerRadius: skin.size.s10)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: skin.size.s10).strokeBorder(
                            skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
                }
            }
        }
    }

    // MARK: - 5 Resources

    private static let millions: Double = 1_000_000

    @ViewBuilder private var resources: some View {
        NewCompanyHead(
            title: "Budget & resources",
            line: "What the whole company may spend, which pool accounts it can use, and where its runs happen.")
        field("Company monthly budget · tokens") { budget }
        field("Accounts from the pool · \(draft.accounts.count) assigned") { accounts }
        field("Company runs on runners tagged") {
            NewCompanyTagCards(runners: store.newCompany.runners, selection: $draft.tags, large: true)
        }
    }

    private var budget: some View {
        let blue = skin.color(skin.palette.accentPrimary)
        let total = draft.budgetTokens
        let ceo = min(total, TokenAmount.parse(draft.ceoBudget) ?? 0)
        let warn = Int64(Double(total) * 0.8)
        return VStack(alignment: .leading, spacing: skin.size.s12) {
            VStack(spacing: skin.size.s6) {
                HStack(spacing: skin.size.s20) {
                    Text(Fmt.tokens(total)).citadelFont("t24", weight: "bold", mono: true)
                        .foregroundStyle(skin.color(skin.text.primary)).frame(
                            minWidth: skin.size.s90, alignment: .leading)
                    AinkradDragGauge(
                        value: Double(total) / Self.millions, range: 10...500, step: 10,
                        mark: Double(warn) / Self.millions,
                        tint: blue, label: "Company monthly budget",
                        valueText: { "\(Fmt.tokens(Int64($0 * Self.millions))) tokens" },
                        onChange: { draft.budgetTokens = Int64($0 * Self.millions) },
                        onCommit: { draft.budgetTokens = Int64($0 * Self.millions) })
                }
                GaugeLegend(low: "10M", middle: "warn at \(Fmt.tokens(warn))", high: "500M")
                    .padding(.leading, skin.size.s90 + skin.size.s20)
            }
            .padding(skin.size.s16)
            .background(
                skin.color(.palette("foreground", skin.opacity.o05)),
                in: RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous))
            GeometryReader { geo in
                HStack(spacing: skin.size.s2) {
                    Rectangle().fill(
                        (AinkradFigurePalette.named(draft.palette) ?? .neonTide).lightColor
                    )
                    .frame(width: geo.size.width * CGFloat(Double(ceo) / Double(max(total, 1))))
                    Rectangle().fill(blue.opacity(skin.opacity.o35))
                }
            }
            .frame(height: skin.size.s10).clipShape(Capsule())
            HStack(spacing: skin.size.s16) {
                legend((AinkradFigurePalette.named(draft.palette) ?? .neonTide).lightColor, "CEO \(Fmt.tokens(ceo))")
                legend(blue.opacity(skin.opacity.o35), "for hires \(Fmt.tokens(max(0, total - ceo)))")
            }
        }
    }

    private func legend(_ tint: Color, _ text: String) -> some View {
        HStack(spacing: skin.size.s6) {
            RoundedRectangle(cornerRadius: skin.size.s2).fill(tint).frame(width: skin.size.s8, height: skin.size.s8)
            Text(text).citadelFont("t11_5").foregroundStyle(skin.color(skin.text.muted))
        }
    }

    @ViewBuilder private var accounts: some View {
        let pool = store.newCompany.pool
        if pool.isEmpty {
            Text("The pool has no accounts yet — add some in Accounts, then assign them from Company settings.")
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
        }
        AinkradCardGrid(columns: 2) {
            ForEach(pool) { account in
                let on = draft.accounts.contains(account.id)
                AinkradChoiceCard(isOn: on, height: skin.size.s50, action: { toggle(account.id) }) {
                    HarnessTag(harness: account.harness, size: skin.size.s28)
                    AinkradChoiceText(
                        title: account.label,
                        caption: account.planTier ?? (account.billing == "metered" ? "API key" : "Subscription"),
                        mono: true)
                    AinkradCheckBox(isOn: on)
                }
            }
        }
        if !pool.isEmpty, !pool.contains(where: { draft.accounts.contains($0.id) && $0.harness == draft.harness }) {
            let warning = skin.color(skin.palette.warning)
            HStack(spacing: skin.size.s8) {
                Image(systemName: "exclamationmark.triangle").citadelFont("t12")
                Text(
                    "No \(AgentLook.harnessName(draft.harness)) account assigned — the CEO would start on its fallback chain."
                )
                .citadelFont("t12")
            }
            .foregroundStyle(warning)
            .padding(skin.size.s10).frame(maxWidth: .infinity, alignment: .leading)
            .background(
                warning.opacity(skin.opacity.o10), in: RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
            )
        }
    }

    private func toggle(_ id: Int64) {
        if draft.accounts.contains(id) { draft.accounts.remove(id) } else { draft.accounts.insert(id) }
    }

    // MARK: - 6 Review

    @ViewBuilder private var review: some View {
        let company = draft.stub
        NewCompanyHead(
            title: "Ready to create", line: "You land on its empty Home with the CEO waiting for a first requirement.")
        group("Company") {
            row("Identity", 0) {
                CompanyMark(company: company, size: skin.size.s26, live: false, fontKey: "t11", logo: draft.logoImage)
                bold(draft.cleanName.isEmpty ? "Untitled" : draft.cleanName)
                KindChip(company: company)
                faint(draft.industryLine)
            }
            if !draft.description.isEmpty { row("About", 0) { faint(draft.description) } }
        }
        group("CEO") {
            row("Profile", 1) {
                AinkradAgentFigure(
                    name: draft.ceoName, state: .idle, palette: AinkradFigurePalette.named(draft.palette) ?? .neonTide,
                    harness: AgentLook.harness(draft.harness), size: skin.size.s26, isActive: false)
                bold(draft.ceoName)
                faint("\(draft.sandbox) · " + draft.ceoTags.sorted().map { "#\($0)" }.joined(separator: " "))
            }
            row("Instructions", 2) {
                faint("\(draft.instructions.count) chars · \(draft.guidelines.count) guidelines")
            }
            row("Model", 3) {
                HarnessTag(harness: draft.harness, size: skin.size.s22)
                bold(draft.modelName)
                faint(
                    "\(draft.effort) effort · \(draft.ceoBudget) tok/mo · \(draft.cap) per run · \(AgentLook.harnessName(draft.harness)) first fallback"
                )
            }
        }
        group("Setup") {
            row("Budget", 5) {
                bold("\(Fmt.tokens(draft.budgetTokens)) tokens / month")
                faint("warn at \(Fmt.tokens(Int64(Double(draft.budgetTokens) * 0.8)))")
            }
            row("Accounts", 5) {
                let chosen = store.newCompany.pool.filter { draft.accounts.contains($0.id) }
                if chosen.isEmpty {
                    Text("none — it can't run yet").citadelFont("t12").foregroundStyle(skin.color(skin.palette.warning))
                }
                ForEach(chosen) { account in
                    let tint = AgentLook.harness(account.harness)?.color ?? skin.color(skin.text.muted)
                    Text(account.label).citadelFont("t10_5", mono: true).foregroundStyle(tint)
                        .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
                        .background(tint.opacity(skin.opacity.o16), in: RoundedRectangle(cornerRadius: skin.size.s6))
                }
            }
            row("Runners", 5) {
                Text(draft.tags.sorted().map { "#\($0)" }.joined(separator: " ")).citadelFont("t12", mono: true)
            }
        }
    }

    private func group<Content: View>(_ title: String, @ViewBuilder _ rows: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            AinkradGroupLabel(title: title)
            rows()
        }
    }

    private func row<Content: View>(_ label: String, _ step: Int, @ViewBuilder _ value: () -> Content) -> some View {
        HStack(spacing: skin.size.s10) {
            Text(label).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                .frame(width: skin.size.s90, alignment: .leading)
            AinkradFlowLayout(spacing: skin.size.s8, lineSpacing: skin.size.s4) { value() }
                .frame(maxWidth: .infinity, alignment: .leading)
            AinkradTapArea {
                draft.step = step
            } label: {
                Text("Edit").citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.palette.accentSecondary))
            }
            .buttonStyle(.plain)
        }
        .padding(.horizontal, skin.size.s12).padding(.vertical, skin.size.s9)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)),
            in: RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous))
    }

    private func bold(_ text: String) -> some View {
        Text(text).citadelFont("t13", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
    }

    private func faint(_ text: String) -> some View {
        Text(text).citadelFont("t12").foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
    }
}
