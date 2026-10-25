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

extension AinkradCard {
    /// The mockups' coloured rim on a card that needs attention (amber waiting, red stalled, violet CEO / CTO);
    /// `nil` keeps the skin's own stroke.
    func rim(_ tone: AinkradChartTone?) -> Self { tone.map(rimTint) ?? self }
}

extension NeedsItem.Tone {
    var chartTone: AinkradChartTone {
        switch self {
        case .accent: .accentPrimary
        case .warning: .warning
        case .danger: .danger
        }
    }
}

extension View {
    /// Text in the skin's font at a size key, mono when asked.
    func citadelFont(_ size: String, weight: String? = nil, mono: Bool = false) -> some View {
        modifier(CitadelFont(size: size, weight: weight, mono: mono))
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

    /// `09:31`, never `9:31 AM` — Citadel writes the 24-hour clock the prototype does.
    static func clock(_ date: Date) -> String {
        let parts = Calendar.current.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", parts.hour ?? 0, parts.minute ?? 0)
    }

    /// `Tue` within a week, `Oct 28` after.
    static func eta(_ day: String, now: Date = Date()) -> String {
        guard let date = try? Date(day, strategy: Date.ISO8601FormatStyle().year().month().day()) else { return day }
        return date.timeIntervalSince(now) < 6 * 86_400
            ? date.formatted(.dateTime.weekday(.abbreviated)) : date.formatted(.dateTime.month(.abbreviated).day())
    }
}

/// Spend split three ways in the mockups' colours: priced cyan, unpriced amber, subscription violet (screens 02,
/// 09) — tokens on one scale, so an unpriced run is never drawn as $0.
struct SpendSplitBar: View {
    let spend: SpendInfo

    var body: some View {
        AinkradStackedStatusBar(toneRuns: [
            AinkradToneRun(value: Double(spend.pricedTokens), tone: .accentSecondary),
            AinkradToneRun(value: Double(spend.unpricedTokens), tone: .warning),
            AinkradToneRun(value: Double(spend.subscriptionTokens), tone: .accentViolet),
        ])
    }
}

extension AinkradChartTone {
    /// The tone's colour, as the kit's charts read it (the kit keeps its own mapping internal).
    func tint(_ skin: AinkradSkin) -> Color {
        switch self {
        case .accentPrimary: skin.color(skin.palette.accentPrimary)
        case .accentSecondary: skin.color(skin.palette.accentSecondary)
        case .accentTertiary: skin.color(skin.palette.accentTertiary)
        case .success: skin.color(skin.palette.success)
        case .warning: skin.color(skin.palette.warning)
        case .danger: skin.color(skin.palette.danger)
        case .muted: skin.color(skin.text.faint)
        case .accentViolet: skin.color(skin.palette.accentViolet)
        @unknown default: skin.color(skin.palette.accentSecondary)
        }
    }
}
