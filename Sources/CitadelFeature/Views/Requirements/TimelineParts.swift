import AinkradAppKit
import SwiftUI

/// The conversation pieces the requirement thread (12) and agent threads (07) share — the prototype's `.tl-*`.

/// `**bold**` and `code` in agents' text, as the prototype renders it.
func richText(_ text: String) -> Text {
    let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
    return Text((try? AttributedString(markdown: text, options: options)) ?? AttributedString(text))
}

/// Your message: right-aligned "time · You" over a blue→violet bubble (`.tl-you`).
struct YouTurn: View {
    let text: String
    let at: String?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: skin.size.s16, bottomLeadingRadius: skin.size.s16, bottomTrailingRadius: skin.size.s4,
            topTrailingRadius: skin.size.s16, style: .continuous)
        VStack(alignment: .trailing, spacing: skin.size.s6) {
            HStack(spacing: skin.size.s8) {
                if let at { Text(at).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint)) }
                Text("You").citadelFont("t12", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
            }
            richText(text).citadelFont("t13").lineSpacing(skin.size.s3)
                .foregroundStyle(skin.color(skin.palette.white).opacity(skin.opacity.o95))
                .padding(.horizontal, skin.size.s14)
                .padding(.vertical, skin.size.s11)
                .background(
                    shape.fill(
                        LinearGradient(
                            colors: [
                                skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o40),
                                skin.color(skin.palette.accentViolet).opacity(skin.opacity.o30),
                            ], startPoint: .topLeading, endPoint: .bottomTrailing))
                )
                .overlay(
                    shape.strokeBorder(
                        skin.color(skin.palette.accentPrimary).opacity(skin.opacity.o25), lineWidth: 1))
        }
        .padding(.leading, skin.size.s160)
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// An agent's turn: orb 30, "Name ROLE KEY · time", then the message (`.tl-turn`); `extra` sits under the text.
struct AgentTurn<Extra: View>: View {
    let agent: AgentInfo
    let model: CompanyModel
    var role: String?
    var issueKey: String?
    var at: String?
    let text: String
    var onKey: (() -> Void)?
    @ViewBuilder var extra: () -> Extra
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        HStack(alignment: .top, spacing: skin.size.s12) {
            AgentFigure(agent: agent, model: model, size: skin.size.s30)
            VStack(alignment: .leading, spacing: skin.size.s6) {
                TurnHead(name: agent.name, role: role ?? agent.role, issueKey: issueKey, at: at, onKey: onKey)
                if !text.isEmpty {
                    richText(text).citadelFont("t13").lineSpacing(skin.size.s4)
                        .foregroundStyle(skin.color(skin.text.primary).opacity(skin.opacity.o92))
                        .fixedSize(horizontal: false, vertical: true)
                }
                extra()
            }
        }
        .padding(.trailing, skin.size.s40)
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

extension AgentTurn where Extra == EmptyView {
    init(
        agent: AgentInfo, model: CompanyModel, role: String? = nil, issueKey: String? = nil, at: String? = nil,
        text: String, onKey: (() -> Void)? = nil
    ) {
        self.init(
            agent: agent, model: model, role: role, issueKey: issueKey, at: at, text: text, onKey: onKey,
            extra: { EmptyView() })
    }
}

/// "Kestrel  DEV  CIT-62            09:31".
struct TurnHead: View {
    let name: String
    let role: String
    var issueKey: String?
    var at: String?
    var onKey: (() -> Void)?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradTheme) private var theme

    var body: some View {
        HStack(spacing: skin.size.s8) {
            Text(name).citadelFont("t12", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
            Text(role.uppercased()).citadelFont("t10", weight: "semibold").tracking(skin.size.s1 / 2)
                .foregroundStyle(skin.color(skin.text.faint))
            if let issueKey {
                AinkradTapArea(action: { onKey?() }) {
                    Text(issueKey).citadelFont("t11", mono: true).foregroundStyle(theme.accentSecondary)
                }
                .disabled(onKey == nil)
            }
            if let at { Text(at).citadelFont("t10_5", mono: true).foregroundStyle(skin.color(skin.text.faint)) }
            Spacer(minLength: 0)
        }
    }
}

/// A centred system line between gradient hairlines (`.tl-sys`); tappable when it names a run.
struct SysLine: View {
    let text: String
    var tint: Color?
    var action: (() -> Void)?
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s10) {
            hairline
            Text(text).citadelFont("t11")
                .foregroundStyle(tint ?? skin.color(hovering && action != nil ? skin.text.primary : skin.text.faint))
                .lineLimit(1)
                .layoutPriority(1)
            hairline
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .tappable(action, help: "Open")
    }

    private var hairline: some View {
        LinearGradient(
            colors: [.clear, skin.color(.palette("foreground", skin.opacity.o10)), .clear], startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: skin.size.s1)
    }
}

/// An agent drafting / typing: orb, "Aldric is drafting the plan…" and the bouncing dots.
struct TypingTurn: View {
    let agent: AgentInfo
    let model: CompanyModel
    let note: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(alignment: .top, spacing: skin.size.s12) {
            AgentFigure(agent: agent, model: model, size: skin.size.s30)
            VStack(alignment: .leading, spacing: skin.size.s6) {
                HStack(spacing: skin.size.s8) {
                    Text(agent.name).citadelFont("t12", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.primary))
                    Text(note).citadelFont("t12").foregroundStyle(skin.color(skin.text.faint))
                }
                AinkradTypingDots()
            }
            Spacer(minLength: 0)
        }
    }
}

/// A one-line receipt (`.tl-receipt`): a tinted glyph tile, the text, a faint trailing note.
struct ReceiptRow<Label: View>: View {
    let glyph: String
    var tint: Color?
    var trailing: String?
    var action: (() -> Void)?
    @ViewBuilder var label: () -> Label
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status

    var body: some View {
        let tile = tint ?? status.success
        HStack(spacing: skin.size.s10) {
            Text(glyph).citadelFont("t11").foregroundStyle(tile)
                .frame(width: skin.size.s22, height: skin.size.s22)
                .background(tile.opacity(skin.opacity.o12), in: RoundedRectangle(cornerRadius: skin.size.s7))
            label()
            Spacer(minLength: skin.size.s8)
            if let trailing {
                Text(trailing).citadelFont("t11").foregroundStyle(skin.color(skin.text.faint)).fixedSize()
            }
        }
        .citadelFont("t12")
        .foregroundStyle(skin.color(skin.text.muted))
        .padding(.horizontal, skin.size.s12)
        .padding(.vertical, skin.size.s8)
        .background(
            skin.color(.palette("foreground", hovering ? skin.opacity.o05 : skin.opacity.o03)),
            in: RoundedRectangle(cornerRadius: skin.size.s12, style: .continuous)
        )
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .tappable(action, help: "Open")
        .accessibilityElement(children: .combine)
    }
}

/// Quick replies (`.tl-quick`): the first is the amber primary, the rest soft glass.
struct QuickReplies: View {
    let options: [String]
    let pick: (String) -> Void
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradFlowLayout(spacing: skin.size.s8) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, option in
                QuickReply(title: option, isPrimary: index == 0) { pick(option) }
            }
        }
    }
}

private struct QuickReply: View {
    let title: String
    let isPrimary: Bool
    let action: () -> Void
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        AinkradTapArea(action: action) {
            Text(title).citadelFont("t12", weight: isPrimary ? "semibold" : nil)
                .foregroundStyle(isPrimary ? skin.color(skin.palette.background) : skin.color(skin.text.primary))
                .padding(.horizontal, skin.size.s14)
                .frame(height: skin.size.s32)
                .background(
                    shape.fill(
                        isPrimary
                            ? status.warning.opacity(hovering ? 1 : skin.opacity.o90)
                            : skin.color(.palette("foreground", hovering ? skin.opacity.o12 : skin.opacity.o07)))
                )
                .overlay(
                    shape.strokeBorder(
                        isPrimary ? .clear : skin.color(.palette("foreground", skin.opacity.o12)), lineWidth: 1))
        }
        .offset(y: hovering && !reduceMotion ? -skin.size.s1 : 0)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }
}

/// A rounded chip on a hero (`.rq-hm .chip`): h24, r7, 11 pt; tappable ones brighten on hover.
struct ThreadHeroChip<Label: View>: View {
    var action: (() -> Void)?
    @ViewBuilder var label: () -> Label
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s7, style: .continuous)
        HStack(spacing: skin.size.s6) { label() }
            .citadelFont("t11")
            .foregroundStyle(skin.color(skin.text.primary))
            .padding(.horizontal, skin.size.s9)
            .frame(height: skin.size.s24)
            .background(
                shape.fill(
                    skin.color(
                        .palette("foreground", hovering && action != nil ? skin.opacity.o12 : skin.opacity.o07)))
            )
            .animation(skin.animation(skin.motion.hover), value: hovering)
            .overlay(shape.strokeBorder(skin.color(.palette("foreground", skin.opacity.o07)), lineWidth: 1))
            .contentShape(shape)
            .onHover { hovering = $0 }
            .onTapGesture { action?() }
    }
}

/// The state pill with a glowing dot (`.rq-st`).
struct GlowStatePill: View {
    let text: String
    let tint: Color
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s6) {
            Circle().fill(tint).frame(width: skin.size.s7, height: skin.size.s7)
                .shadow(color: tint, radius: skin.size.s4)
            Text(text).citadelFont("t12", weight: "semibold")
        }
        .foregroundStyle(tint)
        .padding(.horizontal, skin.size.s10)
        .frame(height: skin.size.s24)
        .background(tint.opacity(skin.opacity.o14), in: RoundedRectangle(cornerRadius: skin.size.s7))
    }
}

extension View {
    /// A real button (hand cursor, button trait) when there is an action; the plain view otherwise.
    @ViewBuilder fileprivate func tappable(_ action: (() -> Void)?, help: String) -> some View {
        if let action { AinkradTapArea(help: help, action: action) { self } } else { self }
    }
}
