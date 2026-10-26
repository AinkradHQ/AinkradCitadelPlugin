import AinkradAppKit
import SwiftUI

/// `.tl-sys`: a centred faint line between two hairlines; amber for a provider drop, a stall or an abnormal end.
struct TranscriptSysLine: View {
    let text: String
    var tint: Color?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let color = tint ?? skin.color(skin.text.faint)
        let line = tint ?? skin.color(.palette("foreground", skin.opacity.o10))
        HStack(spacing: skin.size.s8) {
            hairline(line)
            Text(text).citadelFont("t11").foregroundStyle(color).multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            hairline(line)
        }
        .frame(maxWidth: .infinity)
    }

    private func hairline(_ color: Color) -> some View {
        LinearGradient(
            colors: [.clear, color.opacity(tint == nil ? 1 : skin.opacity.o35), .clear], startPoint: .leading,
            endPoint: .trailing
        )
        .frame(height: skin.size.s1)
        .frame(minWidth: skin.size.s20)
    }
}

/// `.tl-turn`: the agent's orb, its name and role in caps, the message; a cyan caret while it is the newest thing a
/// running run said.
struct TranscriptTurn: View {
    let agent: AgentInfo?
    let model: CompanyModel
    let text: String
    let secrets: [String]
    let streaming: Bool
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(alignment: .top, spacing: skin.size.s12) {
            if let agent { AgentFigure(agent: agent, model: model, size: skin.size.s30) }
            VStack(alignment: .leading, spacing: skin.size.s4) {
                HStack(spacing: skin.size.s8) {
                    Text(agent?.name ?? "Agent").citadelFont("t12", weight: "semibold")
                        .foregroundStyle(skin.color(skin.text.primary))
                    Text((agent?.role ?? "").uppercased()).citadelFont("t10", weight: "semibold")
                        .tracking(skin.size.s1 / 2).foregroundStyle(skin.color(skin.text.faint))
                }
                HStack(alignment: .lastTextBaseline, spacing: skin.size.s2) {
                    AinkradMarkdownText(text: Redaction.masked(text))
                    if streaming { Caret() }
                }
                if !secrets.isEmpty { SecretChips(names: secrets) }
            }
            .frame(maxWidth: skin.size.s860 - skin.size.s40, alignment: .leading)
            Spacer(minLength: 0)
        }
    }
}

/// The streaming caret: 7×13 cyan, blinking.
private struct Caret: View {
    @State private var on = true
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        Rectangle().fill(skin.color(skin.palette.accentSecondary))
            .frame(width: skin.size.s7, height: skin.size.s13)
            .opacity(on ? 1 : skin.opacity.o20)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 0.5)).repeatForever())
                {
                    on = false
                }
            }
    }
}

/// `.tl-you`: your message, right-aligned in the blue→violet bubble, "delivered at its next turn · You".
struct TranscriptYou: View {
    let text: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let shape = UnevenRoundedRectangle(
            topLeadingRadius: skin.size.s16, bottomLeadingRadius: skin.size.s16, bottomTrailingRadius: skin.size.s4,
            topTrailingRadius: skin.size.s16, style: .continuous)
        VStack(alignment: .trailing, spacing: skin.size.s4) {
            HStack(spacing: skin.size.s6) {
                Text("delivered at its next turn").foregroundStyle(skin.color(skin.text.faint))
                Text("You").citadelFont("t12", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
            }
            .citadelFont("t10_5")
            Text(text).citadelFont("t13").foregroundStyle(skin.color(skin.text.primary))
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
                    shape.strokeBorder(skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o25), lineWidth: 1)
                )
        }
        .containerRelativeFrame(.horizontal, alignment: .trailing) { width, _ in width * 0.72 }
        .frame(maxWidth: .infinity, alignment: .trailing)
    }
}

/// The redacted secrets of one item, as lock chips.
struct SecretChips: View {
    let names: [String]
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        AinkradFlowLayout(spacing: skin.size.s6, lineSpacing: skin.size.s6) {
            ForEach(Array(Set(names)).sorted(), id: \.self) {
                AinkradRedactedChip($0, reason: "Redacted by the server before it was written to the log")
            }
        }
    }
}

/// `.rt`: one flat tool card — a tinted icon tile, the tool's name in its colour, the argument, the status (a live
/// pulse while it runs), Copy on hover, and a body that opens (the diff, the output capped at 132 pt with Show all,
/// or the waiting note).
struct RunToolCard: View {
    let call: ToolCallItem
    let isLive: Bool
    var note: String?
    let copy: (String) -> Void
    @State private var open: Bool
    @State private var showsAll = false
    @State private var hovering = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    init(call: ToolCallItem, isLive: Bool, note: String? = nil, copy: @escaping (String) -> Void) {
        self.call = call
        self.isLive = isLive
        self.note = note
        self.copy = copy
        _open = State(
            initialValue: call.edit != nil || !call.secrets.isEmpty || call.status == .failed || call.status == .waiting
        )
    }

    private var waiting: Bool { call.status == .waiting }
    private var running: Bool { call.status == .running && isLive }
    private var hasBody: Bool {
        call.edit != nil || call.output != nil || !call.secrets.isEmpty || (waiting && note != nil)
    }

    var body: some View {
        let shape = RoundedRectangle(cornerRadius: skin.size.s14, style: .continuous)
        let tint = waiting ? skin.color(skin.palette.warning) : Hue(ToolLook.hue(call.name)).color(skin)
        let border =
            waiting
            ? skin.color(skin.palette.warning).opacity(skin.opacity.o40)
            : running
                ? skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o30)
                : skin.color(.palette("foreground", skin.opacity.o06))
        VStack(alignment: .leading, spacing: 0) {
            head(tint)
            if hasBody && (open || waiting) {
                bodyView(tint)
                    .padding(.leading, skin.size.s44)
                    .padding(.trailing, skin.size.s12)
                    .padding(.bottom, skin.size.s10)
                    .transition(.opacity.combined(with: .move(edge: .top)))
            }
        }
        .background(
            shape.fill(
                waiting
                    ? skin.color(skin.palette.warning).opacity(skin.opacity.o05)
                    : skin.color(.palette("foreground", hovering ? skin.opacity.o05 : skin.opacity.o03)))
        )
        .overlay(shape.strokeBorder(border, lineWidth: 1))
        .padding(.leading, skin.size.s42)
        .frame(maxWidth: skin.size.s860 + skin.size.s42, alignment: .leading)
        .onHover { hovering = $0 }
        .animation(skin.animation(skin.motion.hover), value: hovering)
    }

    private func head(_ tint: Color) -> some View {
        AinkradTapArea(action: {
            guard hasBody, !waiting else { return }
            withAnimation(reduceMotion ? nil : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.26)))
            {
                open.toggle()
            }
        }) {
            HStack(spacing: skin.size.s10) {
                Image(systemName: ToolLook.icon(call.name)).citadelFont("t11", weight: "semibold").foregroundStyle(tint)
                    .frame(width: skin.size.s28, height: skin.size.s28)
                    .background(tint.opacity(skin.opacity.o14), in: RoundedRectangle(cornerRadius: skin.size.s8))
                    .overlay(
                        RoundedRectangle(cornerRadius: skin.size.s8).strokeBorder(
                            tint.opacity(skin.opacity.o28), lineWidth: 1))
                Text(call.name).citadelFont("t12", weight: "semibold").foregroundStyle(tint)
                    .frame(minWidth: skin.size.s34, alignment: .leading)
                Text(call.argument).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.muted))
                    .lineLimit(1).truncationMode(.tail)
                    .frame(maxWidth: .infinity, alignment: .leading)
                HStack(spacing: skin.size.s6) {
                    if running { ToolLiveDot() }
                    status
                }
                Text("Copy").citadelFont("t10_5").hidden()
                Text(hasBody ? "›" : "").citadelFont("t14").foregroundStyle(skin.color(skin.text.faint))
                    .frame(width: skin.size.s12)
                    .rotationEffect(.degrees(open || waiting ? 90 : 0))
            }
            .padding(.leading, skin.size.s7)
            .padding(.trailing, skin.size.s10)
            .padding(.vertical, skin.size.s7)
            .contentShape(Rectangle())
        }
        .overlay(alignment: .trailing) {
            AinkradTapArea(help: "Copy the call") {
                copy(call.argument)
            } label: {
                Text("Copy").citadelFont("t10_5").foregroundStyle(skin.color(skin.palette.accentSecondary))
            }
            .opacity(hovering ? 1 : 0)
            .padding(.trailing, skin.size.s32)
        }
    }

    @ViewBuilder private var status: some View {
        let mono = { (text: Text) in text.citadelFont("t11", mono: true) }
        if waiting {
            mono(Text("waiting for you").foregroundStyle(skin.color(skin.palette.warning)))
        } else {
            switch call.result {
            case .counts(let added, let removed):
                mono(
                    Text("+\(added)").foregroundStyle(skin.color(skin.palette.success)) + Text(" ")
                        + Text("−\(removed)").foregroundStyle(skin.color(skin.palette.danger)))
            case .success(let line): mono(Text(line).foregroundStyle(skin.color(skin.palette.success)))
            case .summary(let line):
                mono(
                    Text(line).foregroundStyle(
                        call.status == .failed ? skin.color(skin.palette.danger) : skin.color(skin.text.faint)))
            default:
                if call.status == .failed { mono(Text("failed").foregroundStyle(skin.color(skin.palette.danger))) }
            }
        }
    }

    @ViewBuilder private func bodyView(_ tint: Color) -> some View {
        VStack(alignment: .leading, spacing: skin.size.s6) {
            if waiting, let note {
                Text(note).citadelFont("t12").foregroundStyle(skin.color(skin.text.muted))
                    .padding(.horizontal, skin.size.s12).padding(.vertical, skin.size.s8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(tint.opacity(skin.opacity.o08), in: RoundedRectangle(cornerRadius: skin.size.s10))
            }
            if let edit = call.edit {
                AinkradDiffReview(
                    fileDiff: AinkradDiffEngine.compute(old: edit.old, new: edit.new, path: edit.path, context: 1),
                    rejectedHunkIDs: .constant([])
                )
                .hidesHeader().editorLines().bareHunks().lineNumberGutter()
            }
            if let output = call.output { capped(Redaction.masked(output)) }
            if let footnote = call.footnote {
                Text(footnote).citadelFont("t10_5").foregroundStyle(skin.color(skin.text.faint))
            }
            if !call.secrets.isEmpty { SecretChips(names: call.secrets) }
        }
    }

    /// Output past 8 lines is capped at 132 pt behind a fade, with "Show all N lines".
    @ViewBuilder private func capped(_ output: String) -> some View {
        let lines = output.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).count
        let caps = lines > 8
        VStack(alignment: .leading, spacing: skin.size.s4) {
            Text(output).citadelFont("t11", mono: true).foregroundStyle(skin.color(skin.text.muted))
                .textSelection(.enabled)
                .frame(maxWidth: .infinity, alignment: .leading)
                .padding(.horizontal, skin.size.s12).padding(.vertical, skin.size.s8)
                .frame(maxHeight: caps && !showsAll ? skin.size.s128 + skin.size.s4 : nil, alignment: .top)
                .clipped()
                .mask {
                    if caps && !showsAll {
                        LinearGradient(
                            stops: [.init(color: .black, location: 0.6), .init(color: .clear, location: 1)],
                            startPoint: .top, endPoint: .bottom)
                    } else {
                        Rectangle()
                    }
                }
                .background(
                    skin.color(.palette("black", skin.opacity.o25)), in: RoundedRectangle(cornerRadius: skin.size.s10))
            if caps {
                AinkradTapArea(action: { showsAll.toggle() }) {
                    Text(showsAll ? "Show less" : "Show all \(lines) lines").citadelFont("t11")
                        .foregroundStyle(skin.color(skin.palette.accentSecondary))
                }
                .padding(.leading, skin.size.s14)
            }
        }
    }
}

/// The live tool's pulsing 8 pt cyan dot.
struct ToolLiveDot: View {
    @State private var dim = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    var body: some View {
        let cyan = skin.color(skin.palette.accentSecondary)
        Circle().fill(cyan).frame(width: skin.size.s8, height: skin.size.s8)
            .shadow(color: cyan, radius: skin.size.s4)
            .opacity(dim ? skin.opacity.o45 : 1)
            .onAppear {
                guard !reduceMotion else { return }
                withAnimation(skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 0.6)).repeatForever())
                {
                    dim = true
                }
            }
    }
}
