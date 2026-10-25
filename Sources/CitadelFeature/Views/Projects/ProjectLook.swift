import AinkradAppKit
import SwiftUI

/// A project's look (prototype `project-board.js` `PROJ_COL`, `project-new.js` `PN_ICONS` / `PN_COLS`). The server
/// stores no icon or colour yet (MISSING `Project.icon/color`), so both follow the project's place in the list:
/// CIT cyan→blue, the next violet, the next amber→rose, as the prototype seeds them.
@MainActor
enum ProjectLook {
    static let glyphs = ["⛫", "▭", "✎", "◈", "⚙", "◐", "✦", "▤", "⌁", "☁", "⚑", "♫"]
    static let pairs: [AinkradFigurePalette] = [
        .neonTide, .ultraviolet, .ember, .aurora, .orchid, .cobalt, .copper, .steel,
    ]

    static func index(_ project: ProjectInfo, in model: CompanyModel) -> Int {
        model.projects.firstIndex { $0.id == project.id } ?? Int(project.id)
    }

    static func tint(_ project: ProjectInfo, in model: CompanyModel) -> (Color, Color) {
        let pair = pairs[index(project, in: model) % pairs.count]
        return (pair.lightColor, pair.deepColor)
    }

    static func glyph(_ project: ProjectInfo, in model: CompanyModel) -> String {
        glyphs[index(project, in: model) % glyphs.count]
    }

    /// An epic's colour: the server has none yet (MISSING `Epic.color`), so it follows the epic's order.
    static func epicTint(_ epic: Int64?, in work: ProjectWork, skin: AinkradSkin) -> Color {
        let colors = [
            skin.color(skin.palette.accentSecondary), skin.color(skin.palette.accentViolet),
            skin.color(skin.palette.success), skin.color(skin.palette.warning), skin.color(skin.palette.accentPrimary),
        ]
        guard let epic, let at = work.epics.firstIndex(where: { $0.id == epic }) else {
            return skin.color(skin.text.faint)
        }
        return colors[at % colors.count]
    }

    static func flowTint(_ state: String, skin: AinkradSkin) -> Color {
        switch state {
        case "in_progress": skin.color(skin.palette.accentSecondary)
        case "review", "in_review": skin.color(skin.palette.accentViolet)
        case "blocked": skin.color(skin.palette.danger)
        case "done": skin.color(skin.palette.success)
        default: skin.color(skin.text.faint)
        }
    }

    /// The kind's chip: glyph and colour (`QTYPE`).
    static func kind(_ kind: String, skin: AinkradSkin) -> (glyph: String, title: String, tint: Color) {
        switch kind {
        case "story": ("◆", "Story", skin.color(skin.palette.success))
        case "bug": ("✕", "Bug", skin.color(skin.palette.danger))
        case "subtask": ("↳", "Subtask", skin.color(skin.text.muted))
        case "chore": ("⚙", "Chore", skin.color(skin.text.muted))
        case "spike": ("?", "Spike", skin.color(skin.palette.accentViolet))
        default: ("✓", "Task", skin.color(skin.palette.accentPrimary))
        }
    }
}

/// The project's mark: its glyph on its colour pair (`.pc-ic`, `.pj-big`).
struct ProjectMark: View {
    let glyph: String
    let tint: (Color, Color)
    let side: CGFloat
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: side * 0.29, style: .continuous)
        Text(glyph)
            .citadelFont("t20", weight: "semibold")
            .scaleEffect(side / skin.size.s44)
            .foregroundStyle(skin.color(.palette("foreground", 1)))
            .frame(width: side, height: side)
            .background(
                shape.fill(
                    LinearGradient(colors: [tint.0, tint.1], startPoint: .topLeading, endPoint: .bottomTrailing))
            )
            .overlay(
                shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o25)), lineWidth: 1).mask(
                    LinearGradient(
                        colors: [skin.color(.palette("foreground", 1)), .clear], startPoint: .top, endPoint: .center))
            )
            .shadow(color: tint.0.opacity(skin.opacity.o35), radius: side * 0.2, y: side * 0.18)
            .accessibilityHidden(true)
    }
}

/// The flow bar (`.flowbar`): one segment per state with work, in workflow order, 3 pt apart.
struct FlowBar: View {
    let flow: [(state: String, count: Int)]
    var thickness: CGFloat?
    var vertical = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let parts = flow.filter { $0.count > 0 }
        let total = max(1, parts.reduce(0) { $0 + $1.count })
        let side = thickness ?? skin.size.s10
        GeometryReader { geo in
            let length = (vertical ? geo.size.height : geo.size.width) - CGFloat(max(0, parts.count - 1)) * skin.size.s3
            let stack = ForEach(Array(parts.enumerated()), id: \.offset) { _, part in
                let share = length * CGFloat(part.count) / CGFloat(total)
                Rectangle().fill(ProjectLook.flowTint(part.state, skin: skin))
                    .frame(width: vertical ? side : share, height: vertical ? share : side)
            }
            if vertical {
                VStack(spacing: skin.size.s3) { stack }.frame(maxHeight: .infinity, alignment: .bottom)
            } else {
                HStack(spacing: skin.size.s3) { stack }
            }
        }
        .frame(width: vertical ? side : nil, height: vertical ? nil : side)
        .clipShape(RoundedRectangle(cornerRadius: side / 2, style: .continuous))
    }
}

/// The burndown (`burndown()`): the ideal line dashed, points left in cyan over a fading area, today marked.
struct BurndownChart: View {
    /// Points left per day so far, from the first.
    let left: [Int]
    let committed: Int
    /// The sprint's length in days.
    let days: Int
    var showsToday = true
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let cyan = skin.color(skin.palette.accentSecondary)
        GeometryReader { geo in
            let w = geo.size.width
            let h = geo.size.height
            let top = max(1, committed)
            let x = { (d: Int) in CGFloat(d) / CGFloat(max(1, days - 1)) * w }
            let y = { (v: Int) in skin.size.s8 + (1 - CGFloat(v) / CGFloat(top)) * (h - skin.size.s16) }
            let points = left.enumerated().map { CGPoint(x: x($0.offset), y: y($0.element)) }
            ZStack {
                Path { p in
                    p.move(to: CGPoint(x: 0, y: y(top)))
                    p.addLine(to: CGPoint(x: w, y: y(0)))
                }
                .stroke(
                    cyan.opacity(skin.opacity.o55),
                    style: StrokeStyle(lineWidth: 1, dash: [skin.size.s4, skin.size.s4]))
                if let last = points.last {
                    Path { p in
                        p.addLines(points)
                        p.addLine(to: CGPoint(x: last.x, y: h))
                        p.addLine(to: CGPoint(x: 0, y: h))
                        p.closeSubpath()
                    }
                    .fill(
                        LinearGradient(
                            colors: [cyan.opacity(skin.opacity.o30), .clear], startPoint: .top, endPoint: .bottom))
                    Path { p in p.addLines(points) }
                        .stroke(cyan, style: StrokeStyle(lineWidth: skin.size.s2, lineCap: .round, lineJoin: .round))
                    if showsToday {
                        Path { p in
                            p.move(to: CGPoint(x: last.x, y: 0))
                            p.addLine(to: CGPoint(x: last.x, y: h))
                        }
                        .stroke(
                            skin.color(.palette("foreground", skin.opacity.o30)),
                            style: StrokeStyle(lineWidth: 1, dash: [skin.size.s2, skin.size.s3]))
                    }
                    Circle().fill(cyan).frame(width: skin.size.s7, height: skin.size.s7).position(last)
                }
            }
        }
    }
}

/// `◆ ✓ ✕` on a tint wash (`.qt`).
struct ItemKindChip: View {
    let kind: String
    var side: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let look = ProjectLook.kind(kind, skin: skin)
        let size = side ?? skin.size.s18
        Text(look.glyph).citadelFont("t9_5", weight: "bold").foregroundStyle(look.tint)
            .frame(width: size, height: size)
            .background(look.tint.opacity(skin.opacity.o18), in: RoundedRectangle(cornerRadius: skin.size.s5))
            .help(look.title)
    }
}

/// `▮▮▮` priority bars: the server's flag reads as High; without it, one faint bar.
struct PriorityBars: View {
    let high: Bool
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(high ? "▮▮▮" : "▮").citadelFont("t8").tracking(-1)
            .foregroundStyle(high ? skin.color(skin.palette.warning) : skin.color(skin.text.faint))
            .help(high ? "High priority" : "Normal priority")
    }
}

/// The points chip (`.qc-pts`).
struct PointsChip: View {
    let points: Int?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(points.map(String.init) ?? "–").citadelFont("t10_5", weight: "semibold", mono: true)
            .foregroundStyle(skin.color(skin.text.primary))
            .padding(.horizontal, skin.size.s6)
            .frame(minWidth: skin.size.s22, minHeight: skin.size.s20)
            .background(
                skin.color(.palette("foreground", skin.opacity.o08)), in: RoundedRectangle(cornerRadius: skin.size.s6))
    }
}

/// A state as a tinted tag (`.qr-st`).
struct StateTag: View {
    let state: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = ProjectLook.flowTint(ProjectLogic.flowState(state) ?? state, skin: skin)
        Text(ProjectLogic.title(state)).citadelFont("t10_5").foregroundStyle(tint)
            .padding(.horizontal, skin.size.s8).padding(.vertical, skin.size.s2)
            .background(tint.opacity(skin.opacity.o14), in: RoundedRectangle(cornerRadius: skin.size.s6))
            .fixedSize()
    }
}

/// An epic's tag (`.qc-ep`): its title on its colour.
struct EpicTag: View {
    let title: String
    let tint: Color
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        Text(title).citadelFont("t10_5").foregroundStyle(tint).lineLimit(1)
            .padding(.horizontal, skin.size.s7).padding(.vertical, skin.size.s1)
            .background(tint.opacity(skin.opacity.o15), in: RoundedRectangle(cornerRadius: skin.size.s5))
    }
}

/// The dashed "＋" circle of an unassigned item (`.qc-un`).
struct UnassignedDot: View {
    var side: CGFloat?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let size = side ?? skin.size.s20
        Text("＋").citadelFont("t10").foregroundStyle(skin.color(skin.text.faint))
            .frame(width: size, height: size)
            .overlay(
                Circle().strokeBorder(
                    skin.color(.palette("foreground", skin.opacity.o25)),
                    style: StrokeStyle(lineWidth: 1, dash: [skin.size.s2]))
            )
            .help("Unassigned")
    }
}

/// A legend swatch and its label (`.burn-lg`, `.flow-lg`).
struct ProjectLegend: View {
    let tint: Color
    let label: String
    var dashed = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s6) {
            Capsule().fill(tint).frame(width: skin.size.s10, height: skin.size.s2)
                .opacity(dashed ? skin.opacity.o60 : 1)
            Text(label).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
        }
    }
}
