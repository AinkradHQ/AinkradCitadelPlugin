import AinkradAppKit
import SwiftUI

/// An agent, always as its animated figure (decisions #61, #63): its palette, its live state, its harness as the
/// arc, its uploaded image instead of the orb when it has one.
struct AgentFigure: View {
    let agent: AgentInfo
    let model: CompanyModel
    var size: CGFloat
    var isActive = false

    var body: some View {
        AinkradAgentFigure(
            name: agent.name, state: agent.figure, palette: agent.palette, harness: agent.figureHarness, size: size,
            isActive: isActive, image: model.avatars[agent.id].map { Image(nsImage: $0) })
    }
}

/// A tile's head: the label on the left, an optional "All 5 →" on the right.
struct TileHead: View {
    let title: String
    var action: String?
    var perform: () -> Void = {}
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s8) {
            Text(skin.labelCased(title)).citadelFont("t10", weight: "semibold").tracking(skin.size.s1 / 2)
                .foregroundStyle(skin.color(skin.text.muted))
            Spacer(minLength: skin.size.s8)
            if let action {
                AinkradButton(title: action, style: .ghost, action: perform)
                    .borderless().secondaryAccent().compact().fixedSize()
            }
        }
    }
}

extension View {
    /// The mockups' coloured stroke on a card that needs attention (amber waiting, red stalled), drawn on the
    /// card's own shape so it follows Neon's chamfer and Glass's radius.
    func cardRim(_ color: Color?) -> some View { modifier(CardRim(color: color)) }

    /// Text in the skin's font at a size key, mono when asked.
    func citadelFont(_ size: String, weight: String? = nil, mono: Bool = false) -> some View {
        modifier(CitadelFont(size: size, weight: weight, mono: mono))
    }
}

private struct CardRim: ViewModifier {
    let color: Color?
    @Environment(\.ainkradSkin) private var skin

    func body(content: Content) -> some View {
        content.overlay {
            if let color {
                let shape =
                    skin.usesNativeGlass
                    ? AnyShape(RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous))
                    : AnyShape(skin.shape(cut: skin.size.s10))
                shape.stroke(color.opacity(skin.opacity.o60), lineWidth: skin.size.s1).allowsHitTesting(false)
            }
        }
    }
}

private struct CitadelFont: ViewModifier {
    let size: String
    let weight: String?
    let mono: Bool
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTypography) private var typo

    func body(content: Content) -> some View {
        content.font(
            skin.font(AinkradFontToken(sizeKey: size, weight: weight, mono: mono ? "family" : nil), typography: typo))
    }
}

/// How numbers read on the Citadel screens.
enum Fmt {
    /// `$18.40`.
    static func dollars(micros: Int64) -> String {
        (Double(micros) / 1_000_000).formatted(.currency(code: "USD").precision(.fractionLength(2)))
    }

    /// `82.4k`, `1.2M`, `640`.
    static func tokens(_ count: Int64) -> String {
        let value = Double(count)
        if value >= 1_000_000 { return "\((value / 1_000_000).formatted(.number.precision(.fractionLength(0...1))))M" }
        if value >= 1_000 { return "\((value / 1_000).formatted(.number.precision(.fractionLength(0...1))))k" }
        return "\(count)"
    }

    /// `4m`, `2h`, `12s`.
    static func age(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        if s < 60 { return "\(s)s" }
        if s < 3600 { return "\(s / 60)m" }
        if s < 86_400 { return "\(s / 3600)h" }
        return "\(s / 86_400)d"
    }

    /// `4m 12s`.
    static func duration(_ seconds: TimeInterval) -> String {
        let s = max(0, Int(seconds))
        return s < 60 ? "\(s)s" : s < 3600 ? "\(s / 60)m \(s % 60)s" : "\(s / 3600)h \(s % 3600 / 60)m"
    }

    /// `Tue` within a week, `Oct 28` after.
    static func eta(_ day: String, now: Date = Date()) -> String {
        guard let date = try? Date(day, strategy: Date.ISO8601FormatStyle().year().month().day()) else { return day }
        return date.timeIntervalSince(now) < 6 * 86_400
            ? date.formatted(.dateTime.weekday(.abbreviated)) : date.formatted(.dateTime.month(.abbreviated).day())
    }
}
