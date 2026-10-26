import AinkradAppKit
import CitadelClient
import SwiftUI

/// The wizard's live preview (prototype `.nc-side`): the company card over the CEO card, whose figure's state
/// follows the step.
struct NewCompanyPreview: View {
    let draft: NewCompanyDraft
    /// What the Fallback row reads: the picked chain preset's name, else "<harness> first".
    let fallback: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(spacing: skin.size.s14) {
            companyCard
            ceoCard
            Spacer(minLength: 0)
        }
        .padding(skin.size.s24)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(
            LinearGradient(
                colors: [
                    skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o10),
                    skin.color(skin.palette.accentViolet).opacity(skin.opacity.o08),
                ], startPoint: .top, endPoint: .bottom))
    }

    private func card<Content: View>(@ViewBuilder _ content: () -> Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        return VStack(spacing: skin.size.s4) { content() }
            .padding(.vertical, skin.size.s18).padding(.horizontal, skin.size.s14)
            .frame(maxWidth: .infinity)
            .background(shape.fill(skin.color(.palette("foreground", skin.opacity.o05))))
            .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
    }

    private var companyCard: some View {
        let company = draft.stub
        return card {
            CompanyMark(company: company, size: skin.size.s60, live: false, fontKey: "t24", logo: draft.logoImage)
                .padding(.bottom, skin.size.s6)
            Text(draft.name.isEmpty ? "Untitled company" : draft.name).citadelFont("t17", weight: "bold")
                .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
            HStack(spacing: skin.size.s8) {
                KindChip(company: company)
                Text(draft.industryLine).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
            }
            HStack(spacing: skin.size.s6) {
                stat(
                    draft.budgetInDollars ? "$\(draft.budgetDollars)" : Fmt.tokens(draft.budgetTokens),
                    draft.budgetInDollars ? "$ / month" : "tok / month")
                stat("\(draft.accounts.count)", "accounts")
                stat("\(draft.tags.count)", "tags")
            }
            .padding(.top, skin.size.s12)
        }
    }

    private func stat(_ value: String, _ label: String) -> some View {
        VStack(spacing: skin.size.s1) {
            Text(value).citadelFont("t14", weight: "bold", mono: true).foregroundStyle(skin.color(skin.text.primary))
            Text(label).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
        }
        .padding(.vertical, skin.size.s8)
        .frame(maxWidth: .infinity)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s10))
    }

    private var ceoCard: some View {
        let palette = AinkradFigurePalette.named(draft.palette) ?? .neonTide
        return card {
            AinkradAgentFigure(
                name: draft.ceoName, state: draft.figureState, palette: palette,
                harness: AgentLook.harness(draft.harness), size: skin.size.s70 + skin.size.s6, isActive: true)
            Text(draft.ceoName.isEmpty ? "CEO" : draft.ceoName).citadelFont("t17", weight: "bold")
                .foregroundStyle(skin.color(skin.text.primary)).lineLimit(1)
            Text("CEO · \(AgentLook.harnessName(draft.harness)) · \(draft.modelName)").citadelFont("t12")
                .foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
            Grid(alignment: .leading, horizontalSpacing: skin.size.s12, verticalSpacing: skin.size.s6) {
                row("Effort", draft.effort)
                row("Budget", "\(draft.ceoBudget) tok / mo")
                row("Fallback", fallback)
                row("Share", "\(draft.ceoShare)% of company")
                row("Sandbox", draft.sandbox)
            }
            .padding(.top, skin.size.s10)
        }
    }

    private func row(_ label: String, _ value: String) -> some View {
        GridRow {
            Text(label).foregroundStyle(skin.color(skin.text.faint))
            Text(value).fontWeight(.medium).lineLimit(1).frame(maxWidth: .infinity, alignment: .trailing)
        }
        .citadelFont("t11_5")
    }
}

extension NewCompanyDraft {
    /// The company as the switcher draws it, so the preview and the review reuse `CompanyMark` and `KindChip`.
    var stub: Components.Schemas.Company {
        Components.Schemas.Company(
            accountIds: [], color: colour, description: description, id: 0, industries: [],
            kind: .init(value1: kind == "own" ? .own : .client), name: cleanName.isEmpty ? "?" : cleanName)
    }

    var logoImage: NSImage? { logo.flatMap(NSImage.init(data:)) }
}
