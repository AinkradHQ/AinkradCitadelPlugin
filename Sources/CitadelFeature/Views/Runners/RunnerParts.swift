import AinkradAppKit
import SwiftUI

/// How a runner reads at a glance: its state word, colour and device glyph.
struct RunnerLook {
    let runner: RunnerInfo

    /// `draining` for a drained online runner, else `online` / `unhealthy` / `asleep` / `offline`.
    var state: String { runner.state == "online" && runner.drainedAt != nil ? "draining" : runner.state }

    func tint(_ skin: AinkradSkin) -> Color {
        switch state {
        case "online": skin.color(skin.palette.success)
        case "unhealthy": skin.color(skin.palette.danger)
        case "asleep", "draining": skin.color(skin.palette.warning)
        default: skin.color(skin.text.muted)
        }
    }

    // ponytail: a Mac is told by its `macos` tag or its Power Nap preference; read `Runner.os` once the server sends it.
    var isMac: Bool { runner.tags.contains("macos") || runner.powerNap != nil }
    var glyph: String { isMac ? "laptopcomputer" : "server.rack" }

    /// "linux · up 6d": the platform its tags name (the server reports no OS / arch yet) and its uptime.
    func line(now: Date) -> String {
        var parts: [String] = []
        if isMac { parts.append("macOS") } else if runner.tags.contains("linux") { parts.append("linux") }
        if runner.tags.contains("arm64") { parts.append("arm64") }
        if let up = runner.uptime(now: now) { parts.append(up) }
        if parts.isEmpty, let seen = runner.lastSeenAt {
            parts.append("last seen \(Fmt.age(now.timeIntervalSince(seen))) ago")
        }
        return parts.joined(separator: " · ")
    }
}

/// The runner's device tile (`rn-dev`): its glyph on its state colour; online it breathes with a pulsing corner dot,
/// unhealthy it pulses red, asleep it dims with a drifting "z".
struct DeviceTile: View {
    let look: RunnerLook
    var size: CGFloat?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var phase = false

    var body: some View {
        let side = size ?? skin.size.s52
        let tint = look.tint(skin)
        let shape = RoundedRectangle(cornerRadius: side * 0.29, style: .continuous)
        let live = look.state == "online" || look.state == "draining"
        let bad = look.state == "unhealthy"
        Image(systemName: look.glyph)
            .font(.system(size: side * 0.42, weight: .regular))  // design-lint: allow font-size scales-glyph
            .foregroundStyle(tint)
            .frame(width: side, height: side)
            .background(tint.opacity(skin.opacity.o14), in: shape)
            .overlay(
                shape.strokeBorder(
                    tint.opacity(phase && (live || bad) ? skin.opacity.o45 : skin.opacity.o30), lineWidth: 1)
            )
            .shadow(color: tint.opacity(phase && (live || bad) ? skin.opacity.o35 : 0), radius: side * 0.4)
            .overlay(alignment: .topTrailing) {
                if look.state == "online", side > skin.size.s40 {
                    Circle().fill(tint).frame(width: skin.size.s7, height: skin.size.s7)
                        .shadow(color: tint, radius: skin.size.s8)
                        .opacity(phase ? skin.opacity.o40 : 1)
                        .padding(skin.size.s7)
                }
            }
            .overlay(alignment: .topTrailing) {
                if look.state == "asleep" {
                    Text(verbatim: "z").citadelFont("t11", weight: "bold", mono: true).foregroundStyle(tint)
                        .opacity(phase ? 0 : 1)
                        .offset(x: phase ? skin.size.s4 : -skin.size.s2, y: phase ? -skin.size.s14 : -skin.size.s4)
                }
            }
            .opacity(look.state == "asleep" || look.state == "offline" ? skin.opacity.o75 : 1)
            .onAppear {
                guard !reduceMotion, look.state != "offline" else { return }
                let period = bad ? 0.8 : look.state == "asleep" ? 2.6 : 1.6
                withAnimation(
                    skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: period))
                        .repeatForever(autoreverses: look.state != "asleep")
                ) { phase = true }
            }
    }
}

/// Slot pips: busy ones glow cyan → blue, free ones are empty (or a hollow cyan ring), off ones faint.
struct SlotPips: View {
    let total: Int
    let busy: Int
    var isOn = true
    var hollowFree = false
    var pip: CGSize?
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var pulse = false

    var body: some View {
        let size = pip ?? CGSize(width: skin.size.s22, height: skin.size.s8)
        let cyan = skin.color(skin.palette.accentSecondary)
        HStack(spacing: size.width > skin.size.s18 ? skin.size.s4 : skin.size.s3) {
            ForEach(0..<max(total, 0), id: \.self) { index in
                let shape = Capsule()
                if isOn && index < busy {
                    shape.fill(
                        LinearGradient(
                            colors: [cyan, skin.color(skin.palette.accentPrimary)], startPoint: .leading,
                            endPoint: .trailing)
                    )
                    .frame(width: size.width, height: size.height)
                    .shadow(color: cyan.opacity(skin.opacity.o40), radius: skin.size.s6)
                    .opacity(pulse ? skin.opacity.o65 : 1)
                    .animation(
                        reduceMotion
                            ? nil
                            : skin.animation(AinkradAnimationToken(curve: "easeInOut", duration: 1))
                                .repeatForever().delay(Double(index) * 0.3), value: pulse)
                } else if isOn && hollowFree {
                    shape.strokeBorder(
                        skin.color(skin.palette.accentSecondary).opacity(skin.opacity.o45), lineWidth: skin.size.s1_5
                    )
                    .frame(width: size.width, height: size.height)
                } else {
                    shape.fill(skin.color(.palette("foreground", isOn ? skin.opacity.o08 : skin.opacity.o06)))
                        .frame(width: size.width, height: size.height)
                }
            }
        }
        .onAppear { if !reduceMotion { pulse = true } }
    }
}

/// One coloured part of a disk: what it is, its bytes and its colour.
struct DiskPart: Identifiable {
    var id: String { label }
    let label: String
    let bytes: Int64
    let color: Color
}

extension RunnerDiskInfo {
    /// The prototype's split: the shared build cache (blue), active worktrees (cyan), idle ones (violet).
    func parts(_ skin: AinkradSkin) -> [DiskPart] {
        let active = activeCount
        let idle = idleWorktrees.count
        return [
            DiskPart(label: "shared build cache", bytes: shared, color: skin.color(skin.palette.accentPrimary)),
            DiskPart(
                label: "\(active) active worktree\(active == 1 ? "" : "s")", bytes: self.active,
                color: skin.color(skin.palette.accentSecondary)),
            DiskPart(label: "\(idle) idle", bytes: self.idle, color: skin.color(skin.palette.accentViolet)),
        ].filter { $0.bytes > 0 }
    }
}

/// A segmented ring of the parts against the cap, with a 2 pt gap between arcs; the arcs grow in staggered.
struct DiskDonut: View {
    let parts: [DiskPart]
    let cap: Int64
    let center: String
    let caption: String
    var warn = false
    @Environment(\.ainkradSkin) private var skin
    @Environment(\.ainkradStatusColors) private var status
    @Environment(\.ainkradReduceMotion) private var reduceMotion
    @State private var grown = false

    var body: some View {
        let line = skin.size.s11
        let side = skin.size.s92
        let gap = Double(skin.size.s2) / Double(.pi * (side - line))
        ZStack {
            Circle().stroke(skin.color(.palette("foreground", skin.opacity.o06)), lineWidth: line)
            ForEach(Array(arcs.enumerated()), id: \.offset) { index, arc in
                Circle()
                    .trim(from: arc.start, to: grown ? max(arc.start, arc.end - gap) : arc.start)
                    .stroke(arc.color, lineWidth: line)
                    .rotationEffect(.degrees(-90))
                    .animation(
                        reduceMotion
                            ? nil
                            : skin.animation(AinkradAnimationToken(curve: "easeOut", duration: 1)).delay(
                                Double(index) * 0.14),
                        value: grown)
            }
            VStack(spacing: skin.size.s1) {
                Text(center).citadelFont("t14", weight: "bold", mono: true)
                    .foregroundStyle(warn ? status.warning : skin.color(skin.text.primary))
                Text(caption).citadelFont("t8_5").foregroundStyle(skin.color(skin.text.faint))
            }
        }
        .frame(width: side - line, height: side - line)
        .padding(line / 2)
        .onAppear { grown = true }
    }

    private var arcs: [(start: Double, end: Double, color: Color)] {
        var start = 0.0
        return parts.map { part in
            let length = cap > 0 ? Double(part.bytes) / Double(cap) : 0
            defer { start += length }
            return (min(start, 1), min(start + length, 1), part.color)
        }
    }
}

/// A legend swatch and its text.
struct LegendItem: View {
    let tone: AinkradChartTone
    let text: String
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        HStack(spacing: skin.size.s5) {
            RoundedRectangle(cornerRadius: skin.size.s2).fill(tone.tint(skin)).frame(
                width: skin.size.s8, height: skin.size.s8)
            Text(text).citadelFont("t11").foregroundStyle(skin.color(skin.text.muted)).lineLimit(1)
        }
    }
}

/// The mockups' `.why` block: a bold sentence, then the detail, on a tinted fill (red unhealthy, amber waiting).
struct ReasonBlock: View {
    let title: String
    let detail: String
    var tone: AinkradChartTone?
    @Environment(\.ainkradSkin) private var skin

    var body: some View {
        let tint = tone.map { $0.tint(skin) }
        // Amber text for waiting (the mockups' `.why.warn`); a red block keeps its text light on the red fill.
        let text = tone == .warning ? tint : nil
        (Text(title).bold().foregroundStyle(text ?? skin.color(skin.text.primary))
            + Text(" \(detail)").foregroundStyle(text ?? skin.color(skin.text.muted)))
            .citadelFont("t12_5")
            .lineSpacing(skin.size.s3)
            .fixedSize(horizontal: false, vertical: true)
            .padding(.horizontal, skin.size.s12)
            .padding(.vertical, skin.size.s10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                (tint ?? skin.color(skin.palette.white)).opacity(tone == nil ? skin.opacity.o05 : skin.opacity.o10),
                in: RoundedRectangle(cornerRadius: skin.size.s8))
    }
}
