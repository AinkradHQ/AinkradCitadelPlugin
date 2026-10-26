import AinkradAppKit
import SwiftUI

extension ToolCallItem {
    /// The status column: `+38 −6`, `exit 0 · 1.2 s`, `412 lines`, `waiting for you`.
    var statusText: String {
        if status == .waiting { return "waiting for you" }
        switch result {
        case .counts(let added, let removed): return "+\(added) −\(removed)"
        case .success(let line), .summary(let line): return line
        case .none: return status == .failed ? "failed" : ""
        @unknown default: return ""
        }
    }
}

/// The peek's "Steps": what the run did (its tool calls), the one running now, with the tool mix in the head.
/// Planned next steps have no source (MISSING: an agent plan stream), so none are drawn.
struct PeekSteps: View {
    let model: CompanyModel
    let run: RunInfo
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let chunks = model.transcripts[run.id] ?? []
        let calls = Transcript.items(chunks, runState: run.state)
            .compactMap { if case .tool(let call) = $0 { call } else { nil } }
        let done = calls.filter { $0.status != .running }
        let now: ToolCallItem? = {
            guard run.isLive, run.state == "running" else { return nil }
            if let running = calls.last(where: { $0.status == .running }) { return running }
            guard let tool = model.toolNow[run.id] else { return nil }
            let parts = tool.split(separator: " ", maxSplits: 1).map(String.init)
            return ToolCallItem(
                id: "now-\(run.id)", name: parts.first ?? "Tool", argument: parts.dropFirst().first ?? tool,
                status: .running, result: .none, edit: nil, secrets: [], footnote: nil)
        }()
        let planned: [ToolCallItem] =
            run.isLive && run.state == "running"
            ? chunks.filter { $0.kind == "planned_step" }.map {
                ToolCallItem(
                    id: "plan-\($0.seq)", name: $0.fields["name"] ?? "Tool", argument: $0.fields["arg"] ?? "",
                    status: .running, result: .summary("planned"), edit: nil, secrets: [], footnote: nil)
            }
            : []
        let mix = Dictionary(grouping: done, by: \.name).map { ($0.key, $0.value.count) }.sorted { $0.1 > $1.1 }
        RunPanel {
            HStack(spacing: skin.size.s8) {
                Text("Steps").citadelFont("t12_5", weight: "semibold").foregroundStyle(skin.color(skin.text.primary))
                Text(verbatim: "\(done.count) done" + (planned.isEmpty ? "" : " · \(planned.count) planned"))
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
                Spacer(minLength: skin.size.s4)
                ForEach(mix.prefix(5), id: \.0) { name, count in
                    let tint = Hue(ToolLook.hue(name)).color(skin)
                    HStack(spacing: skin.size.s5) {
                        Image(systemName: ToolLook.icon(name)).citadelFont("t10")
                        Text(name).citadelFont("t10_5")
                        Text("\(count)").citadelFont("t10", weight: "semibold", mono: true)
                    }
                    .foregroundStyle(tint)
                    .padding(.horizontal, skin.size.s7)
                    .frame(height: skin.size.s22)
                    .background(tint.opacity(skin.opacity.o13), in: RoundedRectangle(cornerRadius: skin.size.s6))
                }
            }
            if done.isEmpty && now == nil {
                Text(model.transcripts[run.id] == nil ? "reading its transcript…" : "no tool calls")
                    .citadelFont("t11").foregroundStyle(skin.color(skin.text.faint))
            } else {
                VStack(spacing: skin.size.s4) {
                    ForEach(Array(done.enumerated()), id: \.element.id) { index, call in
                        StepRow(call: call, index: index)
                    }
                    if let now { StepRow(call: now, index: done.count, isNow: true) }
                    ForEach(Array(planned.enumerated()), id: \.element.id) { idx, plan in
                        StepRow(call: plan, index: done.count + 1 + idx, isPlanned: true)
                    }
                }
                .background(alignment: .leading) {
                    LinearGradient(
                        colors: [
                            skin.color(.palette("foreground", skin.opacity.o10)),
                            skin.color(.palette("foreground", skin.opacity.o03)),
                        ], startPoint: .top, endPoint: .bottom
                    )
                    .frame(width: skin.size.s2)
                    .padding(.vertical, skin.size.s14)
                    .padding(.leading, skin.size.s13)
                }
            }
        }
    }
}

/// `.rsd-step`: icon tile on the rail, the tool's name in its colour, the argument, the status.
private struct StepRow: View {
    let call: ToolCallItem
    let index: Int
    var isNow = false
    var isPlanned = false
    @State private var hovering = false
    @State private var shown = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion

    private var shortArg: String {
        for prefix in ["citadel/", "ainkrad-citadel-plugin/"] where call.argument.hasPrefix(prefix) {
            return String(call.argument.dropFirst(prefix.count))
        }
        return call.argument
    }

    var body: some View {
        let cyan = skin.color(skin.palette.accentSecondary)
        let tint =
            isNow
            ? cyan
            : isPlanned ? skin.color(skin.text.faint) : Hue(ToolLook.hue(call.name)).color(skin)
        let tile = RoundedRectangle(cornerRadius: skin.size.s8, style: .continuous)
        HStack(spacing: skin.size.s10) {
            Group {
                if isNow {
                    Circle().fill(cyan).frame(width: skin.size.s8, height: skin.size.s8).shadow(
                        color: cyan, radius: skin.size.s4)
                } else if isPlanned {
                    Circle().strokeBorder(tint, lineWidth: 1).frame(width: skin.size.s8, height: skin.size.s8)
                } else {
                    Image(systemName: ToolLook.icon(call.name)).citadelFont("t11", weight: "semibold")
                }
            }
            .foregroundStyle(tint)
            .frame(width: skin.size.s28, height: skin.size.s28)
            .background(tile.fill(skin.color(.palette("surface", 1))))
            .overlay(
                tile.strokeBorder(
                    tint.opacity(isNow ? skin.opacity.o50 : skin.opacity.o35),
                    style: StrokeStyle(lineWidth: 1, dash: isPlanned ? [skin.size.s3, skin.size.s2] : []))
            )
            .shadow(color: isNow ? cyan.opacity(skin.opacity.o30) : .clear, radius: skin.size.s7)
            Text(isNow ? "Now" : call.name).citadelFont("t12", weight: "semibold").foregroundStyle(tint)
                .frame(width: skin.size.s44, alignment: .leading).lineLimit(1)
            Text(isNow ? "▸ \(call.name) \(shortArg)" : shortArg).citadelFont("t11", mono: true)
                .foregroundStyle(skin.color(isNow ? skin.text.primary : skin.text.muted))
                .lineLimit(1).truncationMode(.tail)
                .frame(maxWidth: .infinity, alignment: .leading)
            statusLabel(cyan: cyan)
        }
        .padding(.vertical, skin.size.s4)
        .padding(.trailing, skin.size.s8)
        .opacity(isPlanned ? skin.opacity.o55 : 1)
        .background(
            (isNow
                ? cyan.opacity(skin.opacity.o07) : skin.color(.palette("foreground", hovering ? skin.opacity.o03 : 0))),
            in: RoundedRectangle(cornerRadius: skin.size.s10, style: .continuous)
        )
        .onHover { hovering = $0 }
        .offset(x: shown || reduceMotion ? 0 : skin.size.s10)
        .opacity(shown || reduceMotion ? 1 : 0)
        .onAppear {
            withAnimation(
                skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 0.35)).delay(
                    Double(index) * 0.045 + 0.12)
            ) { shown = true }
        }
    }

    @ViewBuilder private func statusLabel(cyan: Color) -> some View {
        if isNow {
            Text("live").citadelFont("t11", mono: true).foregroundStyle(cyan).lineLimit(1)
        } else if case .counts(let added, let removed) = call.result {
            (Text("+\(added)").foregroundStyle(skin.color(skin.palette.success))
                + Text(" ")
                + Text("−\(removed)").foregroundStyle(skin.color(skin.palette.danger)))
                .citadelFont("t11", mono: true).lineLimit(1)
        } else {
            Text(call.statusText).citadelFont("t11", mono: true)
                .foregroundStyle(skin.color(skin.text.faint)).lineLimit(1)
        }
    }
}
