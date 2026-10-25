import AinkradAppKit
import SwiftUI

/// A step's title and one line under it (`.nc-h`).
struct NewCompanyHead: View {
    let title: String
    let line: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        VStack(alignment: .leading, spacing: skin.size.s3) {
            Text(title).citadelFont("t15", weight: "bold").foregroundStyle(skin.color(skin.text.primary))
            Text(line).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
        }
    }
}

/// An industry chip: icon and label, blue when on (`.nc-ind span`).
struct NewCompanyChip: View {
    let title: String
    let symbol: String
    let isOn: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let blue = skin.color(skin.palette.accentPrimary)
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        AinkradTapArea(action: action) {
            HStack(spacing: skin.size.s7) {
                Image(systemName: symbol).citadelFont("t11", weight: "medium")
                Text(title).citadelFont("t12", weight: "medium")
            }
            .foregroundStyle(isOn ? skin.color(skin.text.primary) : skin.color(skin.text.muted))
            .padding(.horizontal, skin.size.s12)
            .frame(height: skin.size.s34)
            .background(
                shape.fill(
                    isOn
                        ? blue.opacity(skin.opacity.o14)
                        : skin.color(.palette("foreground", hovering ? skin.opacity.o07 : skin.opacity.o05)))
            )
            .overlay(
                shape.strokeBorder(
                    isOn ? blue.opacity(skin.opacity.o50) : skin.color(.palette("foreground", skin.opacity.o08)),
                    lineWidth: 1)
            )
            .contentShape(shape)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: isOn)
    }
}

/// The 64 pt dashed logo tile (`.nc-up`): the upload glyph, or the chosen image.
struct NewCompanyLogoTile: View {
    let image: NSImage?
    let pick: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s18, style: .continuous)
        AinkradTapArea(help: "Upload a logo", action: pick) {
            Group {
                if let image {
                    Image(nsImage: image).resizable().scaledToFill()
                } else {
                    Image(systemName: "square.and.arrow.up").citadelFont("t18")
                        .foregroundStyle(
                            hovering ? skin.color(skin.palette.accentPrimary) : skin.color(skin.text.muted))
                }
            }
            .frame(width: skin.size.s64, height: skin.size.s64)
            .background(shape.fill(skin.color(.palette("foreground", hovering ? skin.opacity.o07 : skin.opacity.o05))))
            .clipShape(shape)
            .overlay(
                shape.strokeBorder(
                    hovering
                        ? skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o50)
                        : skin.color(.palette("foreground", skin.opacity.o20)),
                    style: StrokeStyle(lineWidth: 1.5, dash: image == nil ? [skin.size.s4, skin.size.s3] : [])))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// A 26 pt colour swatch with a double ring when on (`.nc-sw span`).
struct NewCompanySwatch: View {
    let color: Color
    let isOn: Bool
    let pick: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous)
        AinkradTapArea(action: pick) {
            shape.fill(color).frame(width: skin.size.s26, height: skin.size.s26)
                .overlay(shape.strokeBorder(skin.color(.palette("background", 1)), lineWidth: 2).opacity(isOn ? 1 : 0))
                .background(
                    shape.inset(by: -skin.size.s3).stroke(skin.color(skin.palette.white), lineWidth: 2).opacity(
                        isOn ? 1 : 0)
                )
                .scaleEffect(hovering ? 1.1 : 1)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// ⟳ that turns a quarter on hover: the next suggested name.
struct NewCompanyDice: View {
    let roll: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradTapArea(help: "Suggest another name", action: roll) {
            Text("⟳").citadelFont("t15").foregroundStyle(
                hovering ? skin.color(skin.text.primary) : skin.color(skin.text.muted)
            )
            .frame(width: skin.size.s30, height: skin.size.s30)
            .background(
                skin.color(.palette("foreground", hovering ? skin.opacity.o08 : 0)),
                in: RoundedRectangle(cornerRadius: skin.size.s8)
            )
            .rotationEffect(.degrees(hovering ? 90 : 0))
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// Harness cards with how many pool accounts each has (the wizard's pool is read for no company yet).
struct NewCompanyHarnessCards: View {
    let pool: [PoolAccount]
    @Binding var selection: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        CardGrid(columns: 4) {
            ForEach(HireCatalog.harnesses, id: \.self) { harness in
                ChoiceCard(isOn: selection == harness, height: skin.size.s54, action: { selection = harness }) {
                    HarnessTag(harness: harness, size: skin.size.s26)
                    CardText(
                        title: AgentLook.harnessName(harness),
                        caption: "\(pool.filter { $0.harness == harness }.count) in pool")
                }
            }
        }
    }
}

/// Runner-tag cards with the runners behind each tag; `large` is the company's (icon tile, runner chips).
struct NewCompanyTagCards: View {
    let runners: [RunnerInfo]
    @Binding var selection: Set<String>
    var large: Bool
    @Environment(\.ainkradSkin) private var skin

    private static let symbols = [
        "linux": "terminal", "macos": "desktopcomputer", "docker": "shippingbox", "arm64": "cpu",
    ]

    var body: some View {
        CardGrid(columns: large ? 2 : 4) {
            ForEach(HireCatalog.runnerTags, id: \.tag) { item in
                let matching = runners.filter { $0.tags.contains(item.tag) }
                let online = matching.filter { $0.status == "online" }.count
                let on = selection.contains(item.tag)
                let caption = "\(Wording.count(matching.count, "runner")) · \(online) online"
                if large {
                    ChoiceCard(isOn: on, axis: .vertical, action: { toggle(item.tag) }) {
                        HStack(spacing: skin.size.s10) {
                            CardGlyph(glyph: Self.symbols[item.tag] ?? "cpu", isOn: on, size: skin.size.s38)
                            CardText(title: item.title, caption: caption)
                            CheckBox(isOn: on)
                        }
                        if !matching.isEmpty {
                            AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s4) {
                                ForEach(matching) { runner in runnerChip(runner) }
                            }
                            .padding(.top, skin.size.s4)
                        }
                    }
                } else {
                    ChoiceCard(isOn: on, height: skin.size.s50, action: { toggle(item.tag) }) {
                        CheckBox(isOn: on)
                        CardText(title: item.title, caption: caption)
                    }
                }
            }
        }
    }

    private func runnerChip(_ runner: RunnerInfo) -> some View {
        let tint =
            runner.status == "online"
            ? skin.color(skin.palette.success)
            : runner.status == "unhealthy" ? skin.color(skin.palette.warning) : skin.color(skin.text.faint)
        return HStack(spacing: skin.size.s5) {
            Circle().fill(tint).frame(width: skin.size.s6, height: skin.size.s6)
            Text(runner.name).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.muted))
        }
        .padding(.horizontal, skin.size.s7).padding(.vertical, skin.size.s2)
        .background(
            skin.color(.palette("foreground", skin.opacity.o05)), in: RoundedRectangle(cornerRadius: skin.size.s6)
        )
        .help("\(runner.name) · \(runner.status)")
    }

    private func toggle(_ tag: String) {
        if selection.contains(tag) { selection.remove(tag) } else { selection.insert(tag) }
    }
}
