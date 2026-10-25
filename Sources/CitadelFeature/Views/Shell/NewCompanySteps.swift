import AinkradAppKit
import AppKit
import SwiftUI
import UniformTypeIdentifiers

/// One step of the New company wizard (prototype `company.js` panes). Steps 0 to 3 here, 4 to 6 in
/// `NewCompanyResourceSteps.swift`.
struct NewCompanyStepPane: View {
    let store: CitadelStore
    @Binding var draft: NewCompanyDraft
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s18) {
            switch draft.step {
            case 0: identity
            case 1: profile
            case 2: instructions
            case 3: modelAndBudget
            default: NewCompanyResourceSteps(store: store, draft: $draft)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - 0 Identity

    @ViewBuilder private var identity: some View {
        NewCompanyHead(
            title: "Who is this company?",
            line: "Name, what it does and how it looks everywhere — the sidebar, Home and every notification.")
        field("Name") {
            AinkradTextField(text: $draft.name, placeholder: "Acme Robotics").fieldHeight(skin.size.s42)
                .onReturn { _ in if draft.hasName { draft.step += 1 } }
                .citadelFont("t15")
        }
        field("Kind") {
            AinkradCardGrid(columns: 2) {
                kindCard("client", "Client", "work you do for someone else · its own budget and reports", "briefcase")
                kindCard("own", "Own", "your own product · you are the client", "hexagon")
            }
        }
        field("What it does · pick all that apply") {
            AinkradFlowLayout(spacing: skin.size.s8, lineSpacing: skin.size.s8) {
                ForEach(NewCompanyDraft.industries, id: \.id) { industry in
                    NewCompanyChip(
                        title: industry.title, symbol: industry.symbol, isOn: draft.industries.contains(industry.id)
                    ) {
                        // At least one stays on.
                        if draft.industries.contains(industry.id) {
                            if draft.industries.count > 1 { draft.industries.remove(industry.id) }
                        } else {
                            draft.industries.insert(industry.id)
                        }
                    }
                }
            }
            AinkradTextArea(
                text: $draft.description,
                placeholder:
                    "One or two lines the CEO reads on every run — the product, the customers, what good looks like",
                minHeight: skin.size.s50)
            AinkradTextField(text: $draft.website, placeholder: "Website or repo org (optional) · github.com/acme")
        }
        field("Logo & colour") { logoAndColour }
    }

    private func kindCard(_ id: String, _ title: String, _ line: String, _ symbol: String) -> some View {
        let on = draft.kind == id
        return AinkradChoiceCard(isOn: on, axis: .vertical, action: { draft.kind = id }) {
            AinkradChoiceGlyph(symbol, isOn: on, size: skin.size.s34).padding(.bottom, skin.size.s6)
            Text(title).citadelFont("t14", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
            Text(line).citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var logoAndColour: some View {
        HStack(alignment: .center, spacing: skin.size.s14) {
            NewCompanyLogoTile(image: draft.logoImage, pick: pickLogo)
            VStack(alignment: .leading, spacing: skin.size.s10) {
                HStack(spacing: skin.size.s8) {
                    ForEach(Array(NewCompanyDraft.swatches.enumerated()), id: \.offset) { index, hex in
                        NewCompanySwatch(
                            color: CompanyLook.rgb(hex).map {
                                Color(.sRGB, red: $0.red, green: $0.green, blue: $0.blue)
                            }
                                ?? .clear, isOn: draft.swatch == index
                        ) { draft.swatch = index }
                    }
                }
                if draft.logo != nil {
                    AinkradTapArea {
                        draft.logo = nil
                        draft.logoType = nil
                    } label: {
                        Text("Remove logo").citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.palette.accentSecondary))
                    }
                    .buttonStyle(.plain)
                } else {
                    Text("Upload a logo or keep the initial on a colour").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.text.faint))
                }
            }
        }
    }

    /// PNG, JPEG or WebP up to 2 MB (what the server takes); anything else is a toast, not a silent drop.
    private func pickLogo() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = false
        panel.allowsMultipleSelection = false
        panel.allowedContentTypes = [.png, .jpeg, .webP]
        panel.message = "Choose a logo for \(draft.cleanName.isEmpty ? "the company" : draft.cleanName)"
        guard panel.runModal() == .OK, let url = panel.url else { return }
        let type = UTType(filenameExtension: url.pathExtension.lowercased())?.preferredMIMEType
        guard let data = try? Data(contentsOf: url), data.count <= 2 << 20,
            let type, ["image/png", "image/jpeg", "image/webp"].contains(type), NSImage(data: data) != nil
        else {
            store.toast(
                AinkradRichToast(
                    title: "Logo not used", body: "Use a PNG, JPG or WebP up to 2 MB.", status: .danger))
            return
        }
        draft.logo = data
        draft.logoType = type
    }

    // MARK: - 1 CEO profile

    @ViewBuilder private var profile: some View {
        NewCompanyHead(
            title: "Hire its CEO",
            line: "The CEO turns your requirements into plans and proposes every hire — you approve each one.")
        VStack(alignment: .leading, spacing: 0) {
            HStack {
                AinkradTextField(text: $draft.ceoName, placeholder: "CEO name")
                    .onReturn { _ in if draft.hasName { draft.step += 1 } }
                    .citadelFont("t20", weight: "semibold")
                NewCompanyDice {
                    let names = NewCompanyDraft.ceoNames
                    draft.ceoName = names[((names.firstIndex(of: draft.ceoName) ?? -1) + 1) % names.count]
                }
            }
            .padding(.horizontal, skin.size.s8).padding(.top, skin.size.s6)
            AinkradTextArea(
                text: $draft.ceoDescription, placeholder: "What this CEO is for", minHeight: skin.size.s50)
        }
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s12).strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
        field("Reports to") { owner }
        field("Sandbox") { SandboxCards(selection: $draft.sandbox) }
        field("Runs on runners tagged") {
            NewCompanyTagCards(runners: store.newCompany.runners, selection: $draft.ceoTags, large: false)
        }
    }

    private var owner: some View {
        let who = store.userName ?? "you"
        return HStack(spacing: skin.size.s12) {
            Text(String(who.prefix(2)).uppercased()).citadelFont("t12", weight: "bold")
                .foregroundStyle(skin.color(skin.palette.white))
                .frame(width: skin.size.s36, height: skin.size.s36)
                .background(skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o60), in: Circle())
            VStack(alignment: .leading, spacing: skin.size.s1) {
                Text("You · \(who)").citadelFont("t13", weight: "semibold")
                Text("owner · approves plans, hires and budgets").citadelFont("t11")
                    .foregroundStyle(skin.color(skin.text.faint))
            }
            Spacer()
            Text("fixed").citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.palette.accentPrimary))
                .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
                .background(
                    skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o16),
                    in: RoundedRectangle(cornerRadius: skin.size.s6))
        }
        .padding(skin.size.s12)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s12)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s12).strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
    }

    // MARK: - 2 CEO instructions

    @ViewBuilder private var instructions: some View {
        NewCompanyHead(
            title: "CEO instructions",
            line: "What the CEO is told on every run, the rules it keeps, and the skills it can load.")
        InstructionsEditor(
            title: "System instructions", pill: "CEO template", text: $draft.instructions,
            template: NewCompanyDraft.ceoInstructions)
        field("Guidelines · \(draft.guidelines.count) on") {
            GuidelineCards(on: $draft.guidelines, all: $draft.allGuidelines)
        }
        field("Skills") {
            Text(
                "Skills attach to the company, a department or a role — publish them in Company settings once it exists."
            )
            .citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
        }
    }

    // MARK: - 3 CEO model & budget

    @ViewBuilder private var modelAndBudget: some View {
        NewCompanyHead(
            title: "CEO model & budget",
            line: "Which harness runs the CEO, how hard it thinks, what it may spend and where it falls back.")
        field("Harness") {
            NewCompanyHarnessCards(pool: store.newCompany.pool, selection: $draft.harness)
        }
        field("Model") { ModelCards(harness: draft.harness, selection: $draft.model) }
        field("Effort") { EffortCards(selection: $draft.effort) }
        field("Fallback chain") {
            Text("Its own model first, then the company's default chain — pick another in Accounts once it is hired.")
                .citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
        }
        VStack(alignment: .leading, spacing: skin.size.s8) {
            HStack {
                AinkradGroupLabel(title: "CEO budget")
                AinkradSegmentedPicker(
                    items: [10_000_000, 20_000_000, 40_000_000, 60_000_000] as [Int64],
                    selection: Binding(
                        get: { TokenAmount.parse(draft.ceoBudget) ?? 0 }, set: { draft.ceoBudget = Fmt.tokens($0) })
                ) { Fmt.tokens($0) }
                .fixedSize()
            }
            BudgetFields(
                budget: $draft.ceoBudget, warn: $draft.warn, cap: $draft.cap,
                footnote:
                    "Budgets are tokens. The CEO's budget is set once its hire is approved; the company's is set when you create it."
            )
        }
        .onChange(of: draft.harness) { _, harness in
            if HireCatalog.models[harness]?.contains(where: { $0.wire == draft.model }) != true {
                draft.model = HireCatalog.models[harness]?.first?.wire ?? ""
            }
        }
    }
}
