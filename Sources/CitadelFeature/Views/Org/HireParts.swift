import AinkradAppKit
import SwiftUI

// The card groups the hire wizard, the agent drawer and the role form share (prototype `hire.js`): editing an
// agent looks like creating one.

struct HarnessCards: View {
    let model: CompanyModel
    @Binding var selection: String
    var showsPool = true
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        CardGrid(columns: 4) {
            ForEach(HireCatalog.harnesses, id: \.self) { harness in
                let pool = model.orgPage.pool.filter { $0.harness == harness }.count
                ChoiceCard(isOn: selection == harness, height: skin.size.s54, action: { selection = harness }) {
                    HarnessTag(harness: harness, size: skin.size.s26)
                    CardText(title: AgentLook.harnessName(harness), caption: showsPool ? "\(pool) in pool" : nil)
                }
            }
        }
    }
}

struct ModelCards: View {
    let harness: String
    @Binding var selection: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let models = HireCatalog.models[harness] ?? []
        CardGrid(columns: max(1, models.count)) {
            ForEach(models) { item in
                ChoiceCard(isOn: selection == item.wire, axis: .vertical, action: { selection = item.wire }) {
                    Text(item.name).citadelFont("t13", weight: "semibold").foregroundStyle(
                        skin.color(skin.text.primary))
                    Text(item.blurb).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                        .padding(.bottom, skin.size.s6)
                    Grid(alignment: .leading, horizontalSpacing: skin.size.s10, verticalSpacing: skin.size.s5) {
                        meter("Quality", item.quality)
                        meter("Speed", item.speed)
                        meter("Cost", item.cost)
                    }
                }
            }
        }
    }

    private func meter(_ label: String, _ value: Int) -> some View {
        GridRow {
            Text(label).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
            DotMeter(value: value)
        }
    }
}

struct EffortCards: View {
    @Binding var selection: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        CardGrid(columns: 3) {
            ForEach(Array(HireCatalog.efforts.enumerated()), id: \.element.id) { index, effort in
                ChoiceCard(isOn: selection == effort.id, height: skin.size.s54, action: { selection = effort.id }) {
                    EffortBars(level: index)
                    CardText(title: effort.title, caption: effort.blurb)
                }
            }
        }
    }
}

struct SandboxCards: View {
    @Binding var selection: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        CardGrid(columns: 3) {
            ForEach(HireCatalog.sandboxes) { box in
                ChoiceCard(isOn: selection == box.id, axis: .vertical, action: { selection = box.id }) {
                    CardGlyph(glyph: box.symbol, isOn: selection == box.id).padding(.bottom, skin.size.s4)
                    Text(box.title).citadelFont("t13", weight: "semibold").foregroundStyle(
                        skin.color(skin.text.primary))
                    Text(box.blurb).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

struct RunnerTagCards: View {
    let model: CompanyModel
    @Binding var selection: Set<String>
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        CardGrid(columns: 4) {
            ForEach(HireCatalog.runnerTags, id: \.tag) { item in
                let runners = model.orgPage.runners.filter { $0.tags.contains(item.tag) }
                let on = selection.contains(item.tag)
                ChoiceCard(isOn: on, height: skin.size.s50, action: { toggle(item.tag) }) {
                    CheckBox(isOn: on)
                    CardText(
                        title: item.title,
                        caption:
                            "\(Wording.count(runners.count, "runner")) · \(runners.filter { $0.status == "online" }.count) online"
                    )
                }
            }
        }
    }

    private func toggle(_ tag: String) {
        if selection.contains(tag) { selection.remove(tag) } else { selection.insert(tag) }
    }
}

/// `❯_ System instructions [Dev template]  159 chars  Reset` over a mono editor.
struct InstructionsEditor: View {
    let title: String
    let pill: String?
    @Binding var text: String
    let template: String?
    var note: String?
    var minHeight: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        VStack(spacing: 0) {
            HStack(spacing: skin.size.s8) {
                Text("❯_").citadelFont("t10", weight: "semibold", mono: true).foregroundStyle(
                    skin.color(skin.palette.accentPrimary))
                Text(title).citadelFont("t12", weight: "semibold")
                if let pill {
                    Text(pill).citadelFont("t10_5").foregroundStyle(skin.color(skin.palette.accentPrimary))
                        .padding(.horizontal, skin.size.s7).padding(.vertical, skin.size.s1)
                        .background(
                            skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o16),
                            in: RoundedRectangle(cornerRadius: skin.size.s5))
                }
                Spacer()
                if let note {
                    Text(note).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                } else {
                    Text("\(text.count) chars").citadelFont("t10_5", mono: true).foregroundStyle(
                        skin.color(skin.text.faint))
                }
                if let template, template != text {
                    AinkradTapArea {
                        text = template
                    } label: {
                        Text("Reset").citadelFont("t11", mono: true).foregroundStyle(
                            skin.color(skin.palette.accentSecondary))
                    }
                    .buttonStyle(.plain)
                }
            }
            .padding(.horizontal, skin.size.s12)
            .frame(height: skin.size.s36)
            .background(skin.color(.palette("foreground", skin.opacity.o05)))
            AinkradTextArea(
                text: $text, placeholder: "What the agent is told on every run", minHeight: minHeight ?? skin.size.s110
            )
            .monospaced()
        }
        .background(shape.fill(skin.color(.palette("black", skin.opacity.o28))))
        .clipShape(shape)
        .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o08)), lineWidth: 1))
    }
}

/// Guidelines as toggle cards (glyph · text · switch), plus a row to add one.
struct GuidelineCards: View {
    @Binding var on: [String]
    @Binding var all: [String]
    @State private var draft = ""
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        CardGrid(columns: 2) {
            ForEach(all, id: \.self) { text in
                let isOn = on.contains(text)
                ChoiceCard(isOn: isOn, height: skin.size.s46, action: { toggle(text) }) {
                    Text(HireCatalog.guidelines.first { $0.text == text }?.glyph ?? "•").citadelFont("t11")
                        .foregroundStyle(isOn ? skin.color(skin.palette.accentPrimary) : skin.color(skin.text.muted))
                        .frame(width: skin.size.s24, height: skin.size.s24)
                        .background(
                            isOn
                                ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o20)
                                : skin.color(.palette("foreground", skin.opacity.o06)),
                            in: RoundedRectangle(cornerRadius: skin.size.s7))
                    Text(text).citadelFont("t12").lineLimit(1)
                        .foregroundStyle(isOn ? skin.color(skin.text.primary) : skin.color(skin.text.muted))
                        .frame(maxWidth: .infinity, alignment: .leading)
                    AinkradToggle(isOn: Binding(get: { on.contains(text) }, set: { _ in toggle(text) }))
                        .fixedSize()
                }
            }
        }
        ChoiceCard(isAdd: true, height: skin.size.s46) {
            AinkradTextField(text: $draft, placeholder: "Add your own guideline…").onSubmit(add)
            AinkradButton(title: "Add", style: .secondary, action: add).compact().fixedSize()
        }
    }

    private func toggle(_ text: String) {
        if let index = on.firstIndex(of: text) { on.remove(at: index) } else { on.append(text) }
    }

    private func add() {
        let text = draft.trimmingCharacters(in: .whitespaces)
        guard !text.isEmpty, !all.contains(text) else { return }
        all.append(text)
        on.append(text)
        draft = ""
    }
}

/// The 17 palettes as gradient swatches in a 9-column grid, plus ⟳ for a random one.
struct PaletteGrid: View {
    @Binding var selection: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        CardGrid(columns: 9) {
            ForEach(AinkradFigurePalette.all) { palette in
                Swatch(palette: palette, isOn: selection == palette.id) { selection = palette.id }
            }
            AinkradTapArea {
                selection = AinkradFigurePalette.all.filter { $0.id != selection }.randomElement()?.id ?? selection
            } label: {
                Text("⟳").citadelFont("t18").foregroundStyle(skin.color(skin.text.muted))
                    .frame(maxWidth: .infinity).aspectRatio(1, contentMode: .fit)
                    .overlay(
                        RoundedRectangle(cornerRadius: skin.size.s10).strokeBorder(
                            skin.color(.palette("foreground", skin.opacity.o20)),
                            style: StrokeStyle(lineWidth: 1, dash: [skin.size.s4, skin.size.s3])))
            }
            .buttonStyle(.plain)
            .help("Surprise me")
        }
    }
}

private struct Swatch: View {
    let palette: AinkradFigurePalette
    let isOn: Bool
    let pick: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        shape.fill(
            LinearGradient(
                colors: [palette.lightColor, palette.deepColor], startPoint: .topLeading, endPoint: .bottomTrailing)
        )
        .aspectRatio(1, contentMode: .fit)
        .overlay(shape.strokeBorder(skin.color(.palette("background", 1)), lineWidth: 2).opacity(isOn ? 1 : 0))
        .background(
            shape.inset(by: -skin.size.s3).stroke(skin.color(skin.palette.white), lineWidth: 2).opacity(isOn ? 1 : 0)
        )
        .scaleEffect(hovering ? 1.06 : 1)
        .contentShape(shape)
        .onHover { hovering = $0 }
        .onTapGesture(perform: pick)
        .help(palette.name)
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// Three number cards — month budget (tokens), warn %, per-run cap — over the warn-tick meter.
struct BudgetFields: View {
    @Binding var budget: String
    @Binding var warn: String
    @Binding var cap: String
    var footnote: String?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let total = TokenAmount.parse(budget) ?? 0
        let warnPercent = min(99, max(1, Int(warn) ?? 80))
        VStack(alignment: .leading, spacing: skin.size.s6) {
            CardGrid(columns: 3) {
                number("Monthly budget", $budget, unit: "tok / mo")
                number("Warn at", $warn, unit: "%")
                number("Per-run cap", $cap, unit: "tok")
            }
            GeometryReader { geo in
                Text("warn \(Fmt.tokens(total * Int64(warnPercent) / 100))").citadelFont("t10_5", mono: true)
                    .foregroundStyle(skin.color(skin.palette.warning)).fixedSize()
                    .position(x: geo.size.width * CGFloat(warnPercent) / 100, y: skin.size.s8)
            }
            .frame(height: skin.size.s16)
            .padding(.top, skin.size.s4)
            GeometryReader { geo in
                HStack(spacing: skin.size.s2) {
                    Rectangle().fill(
                        LinearGradient(
                            colors: [
                                skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o35),
                                skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o80),
                            ], startPoint: .leading, endPoint: .trailing)
                    )
                    .frame(width: geo.size.width * CGFloat(warnPercent) / 100)
                    Rectangle().fill(skin.color(skin.palette.warning).opacity(skin.opacity.o55))
                }
            }
            .frame(height: skin.size.s8)
            .clipShape(Capsule())
            HStack {
                Text("0")
                Spacer()
                Text("hard stop \(Fmt.tokens(total))")
            }
            .citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint))
            if let footnote {
                Text(footnote).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).padding(
                    .top, skin.size.s4)
            }
        }
    }

    private func number(_ label: String, _ text: Binding<String>, unit: String) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s8) {
            Text(label).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted))
            HStack(spacing: skin.size.s8) {
                AinkradTextField(text: text, placeholder: "").monospaced()
                Text(unit).citadelFont("t12", weight: "semibold", mono: true).foregroundStyle(
                    skin.color(skin.text.muted)
                )
                .fixedSize()
            }
        }
        .padding(.horizontal, skin.size.s12).padding(.vertical, skin.size.s10)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s10)
        )
        .overlay(
            RoundedRectangle(cornerRadius: skin.size.s10).strokeBorder(
                skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
    }
}
